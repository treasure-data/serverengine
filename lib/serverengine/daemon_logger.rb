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

  require 'logger'

  class DaemonLogger < Logger
    def initialize(path, config={})
      rotate_age = config[:log_rotate_age] || 5
      rotate_size = config[:log_rotate_size] || 1048576

      @file_dev = MultiprocessFileLogDevice.new(nil,
        shift_age: rotate_age, shift_size: rotate_size)

      super(nil)

      self.level = config[:log_level] || 'debug'
      self.path = path
    end

    def path=(path)
      # overwrite @logdev
      if path.respond_to?(:write) and path.respond_to?(:close)
        # IO
        @logdev = path
        @logdev.sync = true if @logdev.respond_to?(:sync=)
      else
        # path
        @file_dev.path = path
        @logdev = @file_dev
      end
      path
    end

    attr_reader :path

    # override add method
    def add(severity, message = nil, progname = nil, &block)
      if severity < @level
        return true
      end
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = nil
        end
      end
      progname ||= @progname
      self << format_message(SEVERITY_FORMATS_[severity+1], Time.now, progname, message)
      true
    end

    module Severity
      include Logger::Severity
      TRACE = -1
    end
    include Severity

    SEVERITY_FORMATS_ = %w(TRACE DEBUG INFO WARN ERROR FATAL ANY)

    def level=(expr)
      case expr.to_s
      when 'fatal', FATAL.to_s
        e = FATAL
      when 'error', ERROR.to_s
        e = ERROR
      when 'warn', WARN.to_s
        e = WARN
      when 'info', INFO.to_s
        e = INFO
      when 'debug', DEBUG.to_s
        e = DEBUG
      when 'trace', TRACE.to_s
        e = TRACE
      else
        raise ArgumentError, "invalid log level: #{expr}"
      end

      super(e)
    end

    def trace?; @level <= TRACE; end

    def reopen!
      if @path
        @io.reopen(@path, "a")
        @io.sync = true
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

    class MultiprocessFileLogDevice
      def initialize(path, opts={})
        @shift_age = opts[:shift_age] || 7
        @shift_size = opts[:shift_size] || 1024*1024
        @mutex = Mutex.new
        self.path = path
      end

      def write(data)
        # it's hard to remove this synchronize because IO#write raises
        # Errno::ENOENT if IO#reopen is running concurrently.
        @mutex.synchronize do
          unless @file
            return nil
          end
          log_rotate_or_reopen
          @file.write(data)
        end
      rescue Exception => e
        warn "log writing failed: #{e}"
      end

      def path=(path)
        @mutex.synchronize do
          old_file = @file
          file = open_logfile(path)
          begin
            @file = file
            @path = path
            file = old_file
          ensure
            file.close if file
          end
        end
        return path
      end

      def close
        @mutex.synchronize do
          @file.close
          @file = nil
        end
        nil
      end

      attr_reader :path

      def reopen!
        @file.reopen(@path, 'a')
        @file.sync = true
        true
      end

      # for compatibility with Logger::LogDevice
      def dev
        @file
      end

      # for compatibility with Logger::LogDevice
      def filename
        @path
      end

      private

      def open_logfile(path)
        return nil unless path
        file = File.open(path, 'a')
        file.sync = true
        return file
      end

      def log_rotate_or_reopen
        stat = @file.stat
        if stat.size <= @shift_size
          return
        end

        # inter-process locking
        retry_limit = 10
        begin
          # 1) other process is log-rotating now
          # 2) other process log rotated
          # 3) no active processes
          lock = File.open(@path, File::WRONLY | File::APPEND)
          begin
            lock.flock(File::LOCK_EX)
            ino = lock.stat.ino
            if ino == File.stat(@path).ino
              # 3)
              log_rotate
            else
              reopen!
            end
          rescue
            lock.close
          end
        rescue Errno::ENOENT => e
          raise e if retry_limit <= 0
          retry_limit -= 1
          sleep 0.2
          retry
        end

      rescue => e
        warn "log rotation inter-process lock failed: #{e}"
      end

      def log_rotate
        (@shift_age-2).downto(0) do |i|
          if FileTest.exist?("#{@path}.#{i}")
            File.rename("#{@path}.#{i}", "#{@path}.#{i+1}")
          end
        end
        #if FileTest.exist?("#{@path}")
          File.rename("#{@path}", "#{@path}.0")
        #end
        reopen!
      rescue => e
        warn "log rotation failed: #{e}"
      end
    end
  end

end
