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

require 'serverengine/utils'
require 'serverengine/signals'

module ServerEngine
  module Monitor
    class ProcessWorkerMonitor
      def initialize(worker, wid, pmon)
        @worker = worker
        @wid = wid
        @pmon = pmon
      end

      def send_stop(stop_graceful)
        @stop = true
        if stop_graceful
          @pmon.start_graceful_stop! if @pmon
        else
          @pmon.start_immediate_stop! if @pmon
        end
        nil
      end

      def send_reload
        @pmon.send_signal(Signals::RELOAD) if @pmon
        nil
      end

      def join
        @pmon.join if @pmon
        nil
      end

      def alive?
        return false unless @pmon

        if stat = @pmon.try_join
          @worker.logger.info "Worker #{@wid} finished#{@stop ? '' : ' unexpectedly'} with #{ServerEngine.format_join_status(stat)}"
          @pmon = nil
          return false
        else
          return true
        end
      end
    end

    class SpawnWorkerMonitor < ProcessWorkerMonitor
      def initialize(worker, wid, pmon, reload_signal)
        super(worker, wid, pmon)
        @reload_signal = reload_signal
      end

      def send_reload
        if @reload_signal
          @pmon.send_signal(@reload_signal) if @pmon
        end
        nil
      end
    end

    class ThreadWorkerMonitor
      def initialize(worker, thread)
        @worker = worker
        @thread = thread
      end

      def send_stop(stop_graceful)
        Thread.new do
          begin
            @worker.stop
          rescue => e
            ServerEngine.dump_uncaught_error(e)
          end
        end
        nil
      end

      def send_reload
        Thread.new do
          begin
            @worker.reload
          rescue => e
            ServerEngine.dump_uncaught_error(e)
          end
        end
        nil
      end

      def join
        @thread.join
      end

      def alive?
        @thread.alive?
      end
    end
  end
end
