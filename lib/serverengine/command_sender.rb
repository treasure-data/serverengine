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
module ServerEngine
  module CommandSender
    # requires send_signal method or @pid
    module Signal
      private
      def _stop(graceful)
        _send_signal(!ServerEngine.windows? && graceful ? Daemon::Signals::GRACEFUL_STOP : Daemon::Signals::IMMEDIATE_STOP)
      end

      def _restart(graceful)
        _send_signal(graceful ? Daemon::Signals::GRACEFUL_RESTART : Daemon::Signals::IMMEDIATE_RESTART)
      end

      def _reload
        _send_signal(Daemon::Signals::RELOAD)
      end

      def _detach
        _send_signal(Daemon::Signals::DETACH)
      end

      def _dump
        _send_signal(Daemon::Signals::DUMP)
      end

      def _send_signal(sig)
        if respond_to?(:send_signal, true)
          send_signal(sig)
        else
          Process.kill(sig, @pid)
        end
      end
    end

    # requires @command_pipe
    module Pipe
      private
      def _stop(graceful)
        @command_pipe.write graceful ? "GRACEFUL_STOP\n" : "IMMEDIATE_STOP\n"
      end

      def _restart(graceful)
        @command_pipe.write graceful ? "GRACEFUL_RESTART\n" : "IMMEDIATE_RESTART\n"
      end

      def _reload
        @command_pipe.write "RELOAD\n"
      end

      def _detach
        @command_pipe.write "DETACH\n"
      end

      def _dump
        @command_pipe.write "DUMP\n"
      end
    end
  end
end
