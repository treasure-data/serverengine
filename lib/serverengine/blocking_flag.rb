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
require 'thread'

module ServerEngine
  class BlockingFlag
    def initialize
      @set = false
      @mutex = Mutex.new
      @cond = ConditionVariable.new
    end

    def set!
      toggled = false
      @mutex.synchronize do
        unless @set
          @set = true
          toggled = true
        end
        @cond.broadcast
      end
      return toggled
    end

    def reset!
      toggled = false
      @mutex.synchronize do
        if @set
          @set = false
          toggled = true
        end
        @cond.broadcast
      end
      return toggled
    end

    def set?
      @set
    end

    def wait_for_set(timeout=nil)
      @mutex.synchronize do
        unless @set
          @cond.wait(@mutex, timeout)
        end
        return @set
      end
    end

    alias_method :wait, :wait_for_set

    def wait_for_reset(timeout=nil)
      @mutex.synchronize do
        if @set
          @cond.wait(@mutex, timeout)
        end
        return !@set
      end
    end
  end

end
