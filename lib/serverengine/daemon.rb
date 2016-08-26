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
require 'serverengine/command_sender'
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
      @command_sender = @config.fetch(:command_sender, ServerEngine.windows? ? "pipe" : "signal")
      if @command_sender == "pipe"
        extend ServerEngine::CommandSender::Pipe
      else
        extend ServerEngine::CommandSender::Signal
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
        if @command_sender == "pipe"
          inpipe, @command_sender_pipe = IO.pipe
          @command_sender_pipe.sync = true
          @command_sender_pipe.binmode
        end

        if ServerEngine.windows?
          ret = daemonize_with_spawn(inpipe)
        else
          ret = daemonize_with_double_fork(inpipe)
        end

        if @command_sender == "pipe"
          inpipe.close
        end
        return ret
      else
        @pid = Process.pid
        s = create_server(create_logger)
        s.install_signal_handlers
        begin
          s.main
        rescue SystemExit => e
          return e.status
        end
        return 0
      end
    end

    def daemonize_with_spawn(inpipe)
      windows_daemon_cmdline = config[:windows_daemon_cmdline]
      config = {}
      if @command_sender == "pipe"
        config[:in] = inpipe
      end
      @pid = Process.spawn(*Array(windows_daemon_cmdline), config)

      write_pid_file
    end

    def daemonize_with_double_fork(inpipe)
      rpipe, wpipe = IO.pipe
      wpipe.sync = true

      Process.fork do
        begin
          rpipe.close
          if @command_sender == "pipe"
            @command_sender_pipe.close
          end

          Process.setsid
          Process.fork do
            $0 = @daemon_process_name if @daemon_process_name
            wpipe.write "#{Process.pid}\n"

            Privilege.change(@chuser, @chgroup)
            File.umask(@chumask) if @chumask

            s = create_server(create_logger)
            if @command_sender == "pipe"
              s.instance_variable_set(:@command_pipe, inpipe)
            end

            STDIN.reopen(File::NULL)
            STDOUT.reopen(File::NULL, "wb")
            STDERR.reopen(File::NULL, "wb")

            s.install_signal_handlers

            wpipe.write "\n"
            wpipe.close

            begin
              s.main
            rescue SystemExit => e
              exit e.status
            end
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

    def stop(graceful)
      _stop(graceful)
    end

    def restart(graceful)
      _restart(graceful)
    end

    def reload
      _reload
    end

    def detach
      _detach
    end

    def dump
      _dump
    end

    private

    def create_server(logger)
      @server = @create_server_proc.call(@load_config_proc, logger)
    end
  end
end
