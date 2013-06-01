#
# ServerEngine
#
# Copyright (C) 2012 FURUHASHI Sadayuki
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

  require 'logger'

  class DaemonLogger < Logger
    def initialize(dev, config={})
      @hook_stdout = config.fetch(:log_stdout, true)
      @hook_stderr = config.fetch(:log_stderr, true)
      rotate_age = config[:log_rotate_age] || 0
      rotate_size = config[:log_rotate_size] || 1048576

      if dev.is_a?(String)
        @path = dev
        @io = File.open(@path, "a")
        @io.sync = true
      else
        @io = dev
      end

      hook_stdout! if @hook_stdout
      hook_stderr! if @hook_stderr

      super(@io, rotate_age, rotate_size)

      self.level = config[:level] || 'debug'
    end

    attr_accessor :path

    def level=(expr)
      case expr.to_s
      when 'fatal', Logger::FATAL.to_s
        e = Logger::FATAL
      when 'error', Logger::ERROR.to_s
        e = Logger::ERROR
      when 'warn', Logger::WARN.to_s
        e = Logger::WARN
      when 'info', Logger::INFO.to_s
        e = Logger::INFO
      when 'debug', Logger::DEBUG.to_s
        e = Logger::DEBUG
      else
        raise ArgumentError, "invalid log level: #{expr}"
      end

      super(e)
    end

    def hook_stdout!
      STDOUT.sync = true
      @hook_stdout = true

      STDOUT.reopen(@io) if @io != STDOUT
      self
    end

    def hook_stderr!
      STDERR.sync = true
      @hook_stderr = true

      STDERR.reopen(@io) if @io != STDERR
      self
    end

    def reopen!
      if @path
        @io.reopen(@path, "a")
        @io.sync = true
        hook_stdout! if @hook_stdout
        hook_stderr! if @hook_stderr
      end
      nil
    end

    def reopen
      begin
        reopen!
        return true
      rescue
        # TODO log?
        return false
      end
    end

    def close
      if @path
        @io.close unless @io.closed?
      end
      nil
    end
  end

end
