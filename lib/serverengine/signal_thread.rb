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
module ServerEngine

  class SignalThread < Thread
    def initialize(&block)
      @handlers = {}

      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @queue = []
      @finished = false

      block.call(self) if block

      super(&method(:main))
    end

    def trap(sig, command=nil, &block)
      # normalize signal names
      sig = sig.to_s.upcase
      if sig[0,3] == "SIG"
        sig = sig[3..-1]
      end
      sig = sig.to_sym

      old = @handlers[sig]
      if block
        Kernel.trap(sig) { signal_handler_main(sig) }
        @handlers[sig] = block
      else
        Kernel.trap(sig, command)
        @handlers.delete(sig)
      end

      old
    end

    def handlers
      @handlers.dup
    end

    def stop
      @mutex.synchronize do
        @finished = true
        @cond.broadcast
      end
      self
    end

    private

    def signal_handler_main(sig)
      # here always creates new thread to avoid
      # complicated race conditin in signal handlers
      Thread.new do
        begin
          enqueue(sig)
        rescue => e
          ServerEngine.dump_uncaught_error(e)
        end
      end
    end

    def main
      until @finished
        sig = nil

        @mutex.synchronize do
          while true
            return if @finished

            sig = @queue.shift
            break if sig

            @cond.wait(@mutex, 1)
          end
        end

        begin
          @handlers[sig].call(sig)
        rescue => e
          ServerEngine.dump_uncaught_error(e)
        end
      end

      nil

    ensure
      @finished = false
    end

    def enqueue(sig)
      @mutex.synchronize do
        @queue << sig
        @cond.broadcast
      end
    end

  end
end
