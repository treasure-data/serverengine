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
require 'serverengine/signals'
require 'serverengine/signal_thread'
require 'serverengine/worker'

module ServerEngine

  class Server
    include ConfigLoader

    def initialize(worker_module, load_config_proc={}, &block)
      @worker_module = worker_module

      @stop = false
      @stop_status = nil

      super(load_config_proc, &block)

      @log_stdout = !!@config.fetch(:log_stdout, true)
      @log_stderr = !!@config.fetch(:log_stderr, true)
      @log_stdout = false if logdev_from_config(@config) == STDOUT
      @log_stderr = false if logdev_from_config(@config) == STDERR

      @command_sender = @config.fetch(:command_sender, ServerEngine.windows? ? "pipe" : "signal")
      @command_pipe = @config.fetch(:command_pipe, nil)
    end

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

    def dump
      Sigdump.dump unless config[:disable_sigdump]
      nil
    end

    def install_signal_handlers
      s = self
      if @command_pipe
        Thread.new do
          until @command_pipe.closed?
            case @command_pipe.gets.chomp
            when "GRACEFUL_STOP"
              s.stop(true)
            when "IMMEDIATE_STOP"
              s.stop(false)
            when "GRACEFUL_RESTART"
              s.restart(true)
            when "IMMEDIATE_RESTART"
              s.restart(false)
            when "RELOAD"
              s.reload
            when "DETACH"
              s.detach(true)
            when "DUMP"
              s.dump
            end
          end
        end
      else
        SignalThread.new do |st|
          st.trap(@config[:signal_graceful_stop] || Signals::GRACEFUL_STOP) { s.stop(true) }
          st.trap(@config[:signal_detach] || Signals::DETACH) { s.stop(true) }
          # Here disables signals excepting GRACEFUL_STOP == :SIGTERM because
          # only SIGTERM is available on all version of Windows.
          unless ServerEngine.windows?
            st.trap(@config[:signal_immediate_stop] || Signals::IMMEDIATE_STOP) { s.stop(false) }
            st.trap(@config[:signal_graceful_restart] || Signals::GRACEFUL_RESTART) { s.restart(true) }
            st.trap(@config[:signal_immediate_restart] || Signals::IMMEDIATE_RESTART) { s.restart(false) }
            st.trap(@config[:signal_reload] || Signals::RELOAD) { s.reload }
            st.trap(@config[:signal_dump] || Signals::DUMP) { s.dump }
          end
        end
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
      if @stop_status
        raise SystemExit.new(@stop_status)
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
