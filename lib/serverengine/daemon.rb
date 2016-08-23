#
# ServerEngine
#
# Copyright (C) 2012-2013 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
require 'serverengine/process_control'
require 'serverengine/config_loader'
require 'serverengine/privilege'
require 'serverengine/supervisor'

module ServerEngine

  class Daemon
    include ConfigLoader

    def initialize(server_module, worker_module, load_config_proc={}, &block)
      @server_module = server_module
      @worker_module = worker_module

      super(load_config_proc, &block)

      @daemonize = @config.fetch(:daemonize, false)

      if @config.fetch(:supervisor, false)
        @create_server_proc = lambda do |_load_config_proc,logger|
          s = Supervisor.new(server_module, worker_module, _load_config_proc)
          s.logger = logger
          s
        end
      else
        @create_server_proc = Supervisor.create_server_proc(server_module, worker_module, @config)
      end

      @daemon_process_name = @config[:daemon_process_name]
      @daemonize_error_exit_code = @config[:daemonize_error_exit_code] || 1

      @pid_path = @config[:pid_path]
      @chuser = @config[:chuser]
      @chgroup = @config[:chgroup]
      @chumask = @config[:chumask]

      @pid = nil

      server_signals = Signals.mapping(@config, prefix: 'server_')

      @subprocess_controller = ProcessControl.new_sender(@config[:server_process_control_type], server_signals)

      if @daemonize
        @server_cmdline = @config[:server_cmdline]

        if !Process.respond_to?(:fork) && !@server_cmdline
          raise ArgumentError, ":server_cmdline option is required on Windows and JRuby platforms"
        end

        if @server_cmdline && @server_cmdline.is_a?(Array)
          raise ArgumentError, ":server_cmdline must be an array of strings"
        end
      end
    end

    # server is available when run() is called. It is a Supervisor instance if supervisor is set to true. Otherwise a Server instance.
    attr_reader :server

    def run
      begin
        exit main
      rescue => e
        ServerEngine.dump_uncaught_error(e)
        exit @daemonize_error_exit_code
      end
    end

    def self.run_server(server_module, worker_module, load_config_proc={}, &block)
      Daemon.new(server_module, worker_module, load_config_proc, &block).server_main
    end

    def server_main
      $0 = @daemon_process_name if @daemon_process_name

      Privilege.change(@chuser, @chgroup)
      File.umask(@chumask) if @chumask

      s = create_server(create_logger)

      STDIN.reopen(File::NULL)
      STDOUT.reopen(File::NULL, "wb")
      STDERR.reopen(File::NULL, "wb")

      s.install_signal_handlers

      s.main
    end

    def main
      if @daemonize
        subproc_control_pipe = @subprocess_controller.pipe
        begin
          if @server_cmdline
            ret = daemonize_with_spawn(subproc_control_pipe)
          else
            ret = daemonize_with_double_fork(subproc_control_pipe)
          end
          @subprocess_controller.pid = @pid

          return ret

        ensure
          subproc_control_pipe.close if subproc_control_pipe
        end

      else
        @pid = Process.pid
        s = create_server(create_logger)
        s.install_signal_handlers
        s.main
        return 0
      end
    end

    def stop(graceful)
      @subprocess_controller.stop(graceful)
    end

    def restart(graceful)
      @subprocess_controller.restart(graceful)
    end

    def reload
      @subprocess_controller.reload
    end

    def detach
      @subprocess_controller.detach
    end

    def dump
      @subprocess_controller.dump
    end

    private

    def daemonize_with_spawn(subproc_control_pipe)
      options = {}
      options[:in] = subproc_control_pipe if subproc_control_pipe
      @pid = Process.spawn(@server_cmdline, options)

      write_pid_file
    end

    def daemonize_with_double_fork(subproc_control_pipe)
      rpipe, wpipe = IO.pipe
      wpipe.sync = true

      Process.fork do
        begin
          rpipe.close
          @subprocess_controller.close

          Process.setsid
          Process.fork do
            $0 = @daemon_process_name if @daemon_process_name
            wpipe.write "#{Process.pid}\n"

            Privilege.change(@chuser, @chgroup)
            File.umask(@chumask) if @chumask

            s = create_server(create_logger)
            s.control_pipe = subproc_control_pipe if subproc_control_pipe

            STDIN.reopen(File::NULL)
            STDOUT.reopen(File::NULL, "wb")
            STDERR.reopen(File::NULL, "wb")

            s.install_signal_handlers

            wpipe.write "\n"
            wpipe.close

            s.main
          end

          exit 0
        ensure
          exit! @daemonize_error_exit_code
        end
      end

      wpipe.close
      @pid = rpipe.gets.to_i
      data = rpipe.read
      rpipe.close

      if data != "\n"
        return @daemonize_error_exit_code
      end

      write_pid_file

      return 0
    end

    def write_pid_file
      if @pid_path
        File.open(@pid_path, "w") {|f|
          f.write "#{@pid}\n"
        }
      end
    end

    def create_server(logger)
      @server = @create_server_proc.call(@load_config_proc, logger)
    end
  end
end
