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
    module Signal
      # requires @pid
      def stop(graceful)
        Process.kill(!ServerEngine.windows? && graceful ? Daemon::Signals::GRACEFUL_STOP : Daemon::Signals::IMMEDIATE_STOP, @pid)
      end

      def restart(graceful)
        Process.kill(graceful ? Daemon::Signals::GRACEFUL_RESTART : Daemon::Signals::IMMEDIATE_RESTART, @pid)
      end

      def reload
        Process.kill(Daemon::Signals::RELOAD, @pid)
      end

      def detach
        Process.kill(Daemon::Signals::DETACH, @pid)
      end

      def dump
        Process.kill(Daemon::Signals::DUMP, @pid)
      end
    end

    module Pipe
      # requires @command_pipe
    end
  end
end
