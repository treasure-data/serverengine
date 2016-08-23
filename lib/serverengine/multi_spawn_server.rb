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
require 'serverengine/process_manager'
require 'serverengine/multi_worker_server'

module ServerEngine

  class MultiSpawnServer < MultiWorkerServer
    def initialize(worker_module, load_config_proc={}, &block)
      @pm = ProcessManager.new(
        auto_tick: false,
        enable_heartbeat: false,
      )

      super(worker_module, load_config_proc, &block)

      # worker_process_control_type should have a consistent type independently from the platform
      # because application needs to be changed.
      type = @config.fetch(:worker_process_control_type, "signal")
      @process_control_class = ProcessControl.sender_class(type)

      @signals = Signals.mapping(@config, prefix: 'worker_')

      # pmon.hooked_stdin is necessary at start_worker method when it creates
      # ProcessControl::PipeSender instance.
      @pm.hook_stdin = (@process_control_class <= ProcessControl::PipeSender)
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

      subprocess_controller = @process_control_class.new(@signals, pmon)
      return WorkerMonitor.new(w, wid, pmon, subprocess_controller)
    end

    def wait_tick
      @pm.tick(0.5)
    end

    class WorkerMonitor < MultiProcessServer::WorkerMonitor
      def initialize(worker, wid, pmon, subprocess_controller)
        super(worker, wid, pmon)
        @subprocess_controller = subprocess_controller
      end

      def send_stop(stop_graceful)
        @subprocess_controller.stop(stop_graceful)
      end

      def send_reload
        @subprocess_controller.reload
      end
    end
  end

end
