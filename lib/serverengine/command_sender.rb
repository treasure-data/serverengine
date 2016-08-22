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
require 'serverengine/signals'

module ServerEngine
  module CommandSender
    # requires send_signal method or @pid
    module Signal
      private
      def _stop(graceful)
        _send_signal(!ServerEngine.windows? && graceful ? Signals::GRACEFUL_STOP : Signals::IMMEDIATE_STOP)
      end

      def _restart(graceful)
        _send_signal(graceful ? Signals::GRACEFUL_RESTART : Signals::IMMEDIATE_RESTART)
      end

      def _reload
        _send_signal(Signals::RELOAD)
      end

      def _detach
        _send_signal(Signals::DETACH)
      end

      def _dump
        _send_signal(Signals::DUMP)
      end

      def _send_signal(sig)
        if respond_to?(:send_signal, true)
          send_signal(sig)
        else
          Process.kill(sig, @pid)
        end
      end
    end

    # requires @command_sender_pipe
    module Pipe
      private
      def _stop(graceful)
        begin
          _send_command(graceful ? "GRACEFUL_STOP" : "IMMEDIATE_STOP")
        rescue Errno::EPIPE
          # already stopped, then nothing to do
        ensure
          @command_sender_pipe.close rescue nil
          @command_sender_pipe = nil
        end
      end

      def _restart(graceful)
        _send_command(graceful ? "GRACEFUL_RESTART" : "IMMEDIATE_RESTART")
      end

      def _reload
        _send_command("RELOAD")
      end

      def _detach
        _send_command("DETACH")
      end

      def _dump
        _send_command("DUMP")
      end

      def _send_command(cmd)
        @command_sender_pipe.write cmd + "\n"
      end
    end
  end
end
