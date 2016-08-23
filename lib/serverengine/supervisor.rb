#
# ServerEngine
#
# Copyright (C) 2012-2013 Sadayuki Furuhashi
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
require 'serverengine/config_loader'
require 'serverengine/blocking_flag'
require 'serverengine/process_manager'
require 'serverengine/process_control'
require 'serverengine/signals'

require 'serverengine/embedded_server'
require 'serverengine/multi_process_server'
require 'serverengine/multi_thread_server'
require 'serverengine/multi_spawn_server'

module ServerEngine

  class Supervisor
    include ConfigLoader

    def initialize(server_module, worker_module, load_config_proc={}, &block)
      @server_module = server_module
      @worker_module = worker_module

      @detach_flag = BlockingFlag.new
      @stop = false

      @pm = ProcessManager.new(
        auto_tick: false,
        enable_heartbeat: true,
        auto_heartbeat: true,
      )

      super(load_config_proc, &block)

      @create_server_proc = Supervisor.create_server_proc(server_module, worker_module, @config)
      @server_process_name = @config[:server_process_name]

      @restart_server_process = !!@config[:restart_server_process]
      @enable_detach = !!@config[:enable_detach]
      @exit_on_detach = !!@config[:exit_on_detach]
      @disable_reload = !!@config[:disable_reload]

      @control_pipe = @config[:control_pipe]

      @server_signals = Signals.mapping(@config, prefix: 'server_')

      @subprocess_controller = ProcessControl.new_sender(@config[:server_process_control_type], @server_signals)

      @daemon_cmdline = @config[:daemon_cmdline]

      if !Process.respond_to?(:fork) && !@daemon_cmdline
        raise ArgumentError, ":daemon_cmdline option is required on Windows and JRuby platforms"
      end

      if @daemon_cmdline && @daemon_cmdline.is_a?(Array)
        raise ArgumentError, ":daemon_cmdline must be an array of strings"
      end
    end

    # server is available after start_server() call.
    attr_reader :server

    # Daemon overrides control_pipe after initialize
    # if :server_process_control_type is pipe
    attr_accessor :control_pipe

    def reload_config
      super

      @server_detach_wait = @config[:server_detach_wait] || 10.0
      @server_restart_wait = @config[:server_restart_wait] || 1.0

      @pm.configure(@config, prefix: 'server_')

      nil
    end

    module ServerInitializer
      def initialize
        reload_config
      end
    end

    def self.create_server_proc(server_module, worker_module, config)
      wt = config[:worker_type] || 'embedded'
      case wt
      when 'embedded'
        server_class = EmbeddedServer
      when 'process'
        server_class = MultiProcessServer
      when 'thread'
        server_class = MultiThreadServer
      when 'spawn'
        server_class = MultiSpawnServer
      else
        raise ArgumentError, "unexpected :worker_type option #{wt}"
      end

      lambda {|load_config_proc,logger|
        s = server_class.new(worker_module, load_config_proc)
        s.logger = logger
        s.extend(ServerInitializer)
        s.extend(server_module) if server_module
        s.instance_eval { initialize }
        s
      }
    end

    def create_server(logger)
      @server = @create_server_proc.call(@load_config_proc, logger)
    end

    def stop(stop_graceful)
      @stop = true
      @subprocess_controller.stop(stop_graceful)
    end

    def restart(stop_graceful)
      reload_config
      @logger.reopen! if @logger
      if @restart_server_process
        @subprocess_controller.stop(stop_graceful)
      else
        @subprocess_controller.restart(stop_graceful)
      end
    end

    def reload
      unless @disable_reload
        reload_config
      end
      @logger.reopen! if @logger
      @subprocess_controller.reload
    end

    def detach(stop_graceful)
      if @enable_detach
        @detach_flag.set!
        @subprocess_controller.stop(stop_graceful)
      else
        stop(stop_graceful)
      end
    end

    def install_signal_handlers
      # supervisor and server implement same set of commands
      Server.install_signal_handlers_to(self, @control_pipe, @server_signals)
    end

    def main
      # just in case Supervisor is not created by Daemon
      create_logger unless @logger

      start_server

      while true
        # keep the child process alive in this loop
        until @detach_flag.wait(0.5)
          if try_join
            return if @stop   # supervisor stoppped explicitly

            # child process died unexpectedly.
            # sleep @server_detach_wait sec and reboot process
            reboot_server
          end
        end

        wait_until = Time.now + @server_detach_wait
        while (w = wait_until - Time.now) > 0
          break if try_join
          sleep [0.5, w].min
        end

        return if @exit_on_detach

        @detach_flag.reset!
      end
    end

    def logger=(logger)
      super
      @pm.logger = @logger
    end

    private

    def try_join
      if @pmon.nil?
        return true
      elsif stat = @pmon.try_join
        @logger.info "Server finished#{@stop ? '' : ' unexpectedly'} with #{ServerEngine.format_join_status(stat)}"
        @pmon = nil
        return stat
      else
        @pm.tick
        return false
      end
    end

    def start_server
      subproc_control_pipe = @subprocess_controller.pipe
      begin
        @last_start_time = Time.now
        if @daemon_cmdline
          start_server_with_spawn(subproc_control_pipe)
        else
          start_server_with_fork(subproc_control_pipe)
        end
      ensure
        subproc_control_pipe.close if subproc_control_pipe
      end
    end

    def start_server_with_spawn(subproc_control_pipe)
      options = {}
      options[:in] = subproc_control_pipe if subproc_control_pipe
      @pmon = @pm.spawn(*@daemon_cmdline, options)
      @subprocess_controller.attach(@pmon)
    end

    def start_server_with_fork(subproc_control_pipe)
      s = create_server(logger)

      begin
        @pmon = @pm.fork do
          $0 = @server_process_name if @server_process_name

          @subprocess_controller.close
          s.control_pipe = subproc_control_pipe if subproc_control_pipe
          s.install_signal_handlers

          s.main
        end
        @subprocess_controller.attach(@pmon)

        # close pipe here so that s.after_start doesn't
        # inherit it to forked subprocesses
        subproc_control_pipe.close if subproc_control_pipe

      ensure
        # this may raise an exception. @pmon and @last_start_time
        # should be set in advance.
        s.after_start
      end
    end

    def reboot_server
      # try reboot for ever until @detach_flag is set
      while true
        wait = @server_restart_wait - (Time.now - @last_start_time)
        if @detach_flag.wait(wait > 0 ? wait : 0.1)
          break
        end

        begin
          return start_server
        rescue
          ServerEngine.dump_uncaught_error($!)
        end
      end

      return nil
    end
  end

end
