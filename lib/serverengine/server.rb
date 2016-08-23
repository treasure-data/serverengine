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
require 'serverengine/process_control'
require 'serverengine/signals'
require 'serverengine/signal_thread'
require 'serverengine/worker'

module ServerEngine

  class Server
    include ConfigLoader

    def initialize(worker_module, load_config_proc={}, &block)
      @worker_module = worker_module

      @stop = false

      super(load_config_proc, &block)

      @log_stdout = !!@config.fetch(:log_stdout, true)
      @log_stderr = !!@config.fetch(:log_stderr, true)
      @log_stdout = false if logdev_from_config(@config) == STDOUT
      @log_stderr = false if logdev_from_config(@config) == STDERR

      @control_pipe = @config[:control_pipe]

      @signals = Signals.mapping(@config, prefix: 'server_')
    end

    # Supervisor or Daemon overrides control_pipe after initialize
    # if :process_control_type is pipe
    attr_accessor :control_pipe

    def before_run
    end

    def after_run
    end

    def stop(stop_graceful)
      @logger.info "Received #{stop_graceful ? 'graceful' : 'immediate'} stop" if @logger
      @stop = true
      nil
    end

    def after_start
    end

    def restart(stop_graceful)
      @logger.info "Received #{stop_graceful ? 'graceful' : 'immediate'} restart" if @logger
      reload_config
      @logger.reopen! if @logger
      nil
    end

    def reload
      @logger.info "Received reload" if @logger
      reload_config
      @logger.reopen! if @logger
      nil
    end

    def install_signal_handlers
      Server.install_signal_handlers_to(self, @control_pipe, @signals)
    end

    def self.install_signal_handlers_to(s, control_pipe, signals)
      if control_pipe
        receiver = ProcessControl::PipeReceiver.new(control_pipe)
        Thread.new do
          begin
            receiver.each do |cmd|
              case cmd
              when ProcessControl::Commands::GRACEFUL_STOP
                s.stop(true)
              when ProcessControl::Commands::IMMEDIATE_STOP
                s.stop(false)
              when ProcessControl::Commands::GRACEFUL_RESTART
                s.restart(true)
              when ProcessControl::Commands::IMMEDIATE_RESTART
                s.restart(false)
              when ProcessControl::Commands::RELOAD
                s.reload
              when ProcessControl::Commands::DETACH
                s.detach(true)
              when ProcessControl::Commands::DUMP
                Sigdump.dump
              end
            end
          ensure
            receiver.close
          end
        end
      else
        SignalThread.new do |st|
          st.trap(signals[:graceful_stop]) { s.stop(true) } if signal_platform_support(signals[:graceful_stop])
          st.trap(signals[:detach]) { s.detach(true) } if signal_platform_support(signals[:detach])
          st.trap(signals[:immediate_stop]) { s.stop(false) } if signal_platform_support(signals[:immediate_stop])
          st.trap(signals[:graceful_restart]) { s.restart(true) } if signal_platform_support(signals[:graceful_restart])
          st.trap(signals[:immediate_restart]) { s.restart(false) } if signal_platform_support(signals[:immediate_restart])
          st.trap(signals[:reload]) { s.reload } if signal_platform_support(signals[:reload])
          st.trap(signals[:dump]) { Sigdump.dump } if signal_platform_support(signals[:dump])
        end
      end
    end

    def self.signal_platform_support(name)
      signal = Signals.normalized_name(name)
      if ServerEngine.windows?
        case signal
        when "INT", "KILL"
          true
        when "TERM"
          :self
        else
          false
        end
      else
        Signal.list.has_key?(signal.to_s)
      end
    end

    def main
      create_logger unless @logger

      # start threads to transfer logs from STDOUT/ERR to the logger
      start_io_logging_thread(STDOUT) if @log_stdout && try_get_io_from_logger(@logger) != STDOUT
      start_io_logging_thread(STDERR) if @log_stderr && try_get_io_from_logger(@logger) != STDERR

      before_run

      begin
        run
      ensure
        after_run
      end
    end

    module WorkerInitializer
      def initialize
      end
    end

    private

    # If :logger option is set unexpectedly, reading from STDOUT/ERR
    # and writing to :logger could cause infinite loop because
    # :logger may write data to STDOUT/ERR.
    def try_get_io_from_logger(logger)
      logdev = logger.instance_eval { @logdev }
      if logdev.respond_to?(:dev)
        # ::Logger
        logdev.dev
      else
        # logdev is IO if DaemonLogger. otherwise unknown object including nil
        logdev
      end
    end

    def create_worker(wid)
      w = Worker.new(self, wid)
      w.extend(WorkerInitializer)
      w.extend(@worker_module)
      w.instance_eval { initialize }
      w
    end

    def start_io_logging_thread(io)
      r, w = IO.pipe
      io.reopen(w)
      w.close

      Thread.new do
        begin
          while line = r.gets
            @logger << line
          end
        rescue => e
          ServerEngine.dump_uncaught_error(e)
        end
      end
    end
  end

end
