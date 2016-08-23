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

module ServerEngine

  class Worker
    def initialize(server, worker_id)
      @server = server
      @logger = @server.logger
      @worker_id = worker_id
    end

    attr_reader :server, :worker_id
    attr_accessor :logger

    def config
      @server.config
    end

    def before_fork
    end

    def run
      raise NoMethodError, "Worker#run method is not implemented"
    end

    def spawn(process_manager)
      raise NoMethodError, "Worker#spawn(process_manager) method is required for worker_type=spawn"
    end

    def stop
    end

    def reload
    end

    def after_start
    end

    def install_signal_handlers
      w = self

      # This method is called by MultiProcessServer classes. MultiSpawnServer is not
      # a MultiProcessServer (it is a direct subclass of MultiWorkerServer).
      #
      # Only MultiSpawnServer allows override of signals by config. Thus here assumes
      # hardcoded signals (Signals::*) only.
      #
      # Only MultiSpawnServer runs on Windows. Thus here doesn't check availability of
      # signals using Signals.platform_support method.

      # TODO MultiProcessServer is the parent process of workers and it doesn't support
      # process_control_type: 'pipe' option yet. Instead, it always uses signals
      # regardless of process_control_type option. Although it should be improved
      # in the future, here doesn't need to handle @control_pipe for now.

      SignalThread.new do |st|
        st.trap(Signals::GRACEFUL_STOP) { w.stop }
        st.trap(Signals::IMMEDIATE_STOP, 'SIG_DFL')

        st.trap(Signals::GRACEFUL_RESTART) { w.stop }
        st.trap(Signals::IMMEDIATE_RESTART, 'SIG_DFL')

        st.trap(Signals::RELOAD) {
          w.logger.reopen!
          w.reload
        }
        st.trap(Signals::DETACH) { w.stop }

        st.trap(Signals::DUMP) { Sigdump.dump }
      end
    end

    def main
      run
    end
  end

end
