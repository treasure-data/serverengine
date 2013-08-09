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
      require 'thread'

      @handlers = {}

      @mutex = Mutex.new
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
        Kernel.trap(sig) { enqueue(sig) }
        @handlers[sig] = block
      else
        Kernel.trap(sig, command)
        @handlers.delete(sig)
      end

      old
    end

    def handlers
      handlers.dup
    end

    def stop
      @mutex.synchronize do
        ## synchronized state 1
        @finished = true
        ## synchronized state 2
      end
      self
    end

    private

    def main
      @mutex.lock

      until @finished
        ## synchronized state 3

        sig = @queue.shift
        unless sig
          ## synchronized state 4
          sleep 1
          next
        end

        ## synchronized state 5

        @mutex.unlock
        begin
          @handlers[sig].call(sig)
        rescue
          ServerEngine.dump_uncaught_error($!)
        ensure
          @mutex.lock
        end
      end

      ## synchronized state 6
      nil

    ensure
      @mutex.unlock
      @finished = false
    end

    def enqueue(sig)
      @queue << sig
    end

  end
end
