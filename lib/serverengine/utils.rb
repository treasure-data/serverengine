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

  IS_WINDOWS = /mswin|mingw/ === RUBY_PLATFORM
  private_constant :IS_WINDOWS

  def self.windows?
    IS_WINDOWS
  end

  module ClassMethods
    def dump_uncaught_error(e)
      STDERR.write "Unexpected error #{e}\n"
      e.backtrace.each {|bt|
        STDERR.write "  #{bt}\n"
      }
      nil
    end

    def format_signal_name(n)
      Signal.list.each_pair {|k,v|
        return "SIG#{k}" if n == v
      }
      return n
    end

    def format_join_status(code)
      case code
      when Process::Status
        if code.signaled?
          "signal #{format_signal_name(code.termsig)}"
        else
          "status #{code.exitstatus}"
        end
      when Exception
        "exception #{code}"
      when nil
        "unknown reason"
      end
    end

    def kill(signal, pid, logger=nil)
      if ServerEngine.windows?
        sig = signal.to_s.sub(/^SIG/, '').to_sym
        case sig
        when :KILL
          system("taskkill /f /pid #{pid}")
          return true
        when :QUIT
          @logger.warn("SIG#{sig} is not supported on Windows platform. Force erminating process id=#{pid}") if @logger
          system("taskkill /f /pid #{pid}")
          return true
        when :TERM, :INT
          @logger.warn("SIG#{sig} is not supported on Windows platform. Terminating process id=#{pid}") if @logger
          system("taskkill /pid #{pid}")
          return true
        when :USR1, :HUP, :USR2, :INT, :CONT
          @logger.warn("SIG#{sig} is not supported on Windows platform. Signal is not sent.") if @logger
          return true
        else
          # following Process.kill will raise platform-dependent exception
        end
      end

      begin
        Process.kill(signal, pid)
        return true
      rescue Errno::ECHILD
        return false
      rescue Errno::ESRCH
        return false
      end
    end
  end

  extend ClassMethods

end
