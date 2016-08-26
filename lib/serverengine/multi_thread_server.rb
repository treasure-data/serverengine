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
require 'serverengine/multi_worker_server'

module ServerEngine

  class MultiThreadServer < MultiWorkerServer
    private

    def start_worker(wid)
      w = create_worker(wid)

      w.before_fork
      begin
        thread = Thread.new(&w.method(:main))
      ensure
        w.after_start
      end

      return WorkerMonitor.new(w, thread)
    end

    class WorkerMonitor
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

      def recoverable?
        true
      end
    end
  end

end
