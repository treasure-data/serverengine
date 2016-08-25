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
require 'serverengine/process_manager'
require 'serverengine/multi_worker_server'

module ServerEngine

  class MultiSpawnServer < MultiWorkerServer
    def initialize(worker_module, load_config_proc={}, &block)
      if ServerEngine.windows?
        @pm = ProcessManager.new(
          auto_tick: false,
          graceful_kill_signal: Signals::GRACEFUL_STOP,
          immediate_kill_signal: false,
          enable_heartbeat: false,
        )
      else
        @pm = ProcessManager.new(
          auto_tick: false,
          graceful_kill_signal: Signals::GRACEFUL_STOP,
          immediate_kill_signal: Signals::IMMEDIATE_STOP,
          enable_heartbeat: false,
        )
      end

      super(worker_module, load_config_proc, &block)

      @reload_signal = @config[:worker_reload_signal]
      @unrecoverable_exit_codes = @config.fetch(:unrecoverable_exit_codes, [])
      @pm.command_sender = @command_sender
    end

    def stop(stop_graceful)
      if @command_sender == "pipe"
        @pm.command_sender_pipe.write(stop_graceful ? "GRACEFUL_STOP\n" : "IMMEDIATE_STOP\n")
      end
      super
    end

    def run
      super
    ensure
      @pm.close
    end

    def logger=(logger)
      super
      @pm.logger = logger
    end

    private

    def reload_config
      super

      @pm.configure(@config, prefix: 'worker_')

      nil
    end

    def start_worker(wid)
      w = create_worker(wid)

      w.before_fork
      begin
        pmon = w.spawn(@pm)
      ensure
        w.after_start
      end

      return MultiProcessServer::WorkerMonitor.new(w, wid, pmon, @reload_signal, unrecoverable_exit_codes: @unrecoverable_exit_codes)
    end

    def wait_tick
      @pm.tick(0.5)
    end
  end

end
