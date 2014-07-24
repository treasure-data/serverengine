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

  class ::Logger::LogDevice
    def reopen!
      if filename = @filename
        @dev.reopen(filename, 'a')
        @dev.sync = true
      end
    end
  end

  class DaemonLogger < Logger
    def initialize(logdev, config={})
      @rotate_age = config[:log_rotate_age] || 5
      @rotate_size = config[:log_rotate_size] || 1048576

      if RUBY_VERSION < "2.1.0"
        # Ruby < 2.1.0 has a problem around log rotation with multiprocess:
        # https://github.com/ruby/ruby/pull/428
        @logdev_class = MultiprocessFileLogDevice
      else
        @logdev_class = LogDevice
      end

      super(nil)

      self.level = config[:log_level] || 'debug'
      self.logdev = logdev
    end

    def logdev=(logdev)
      # overwrites Logger's @logdev variable
      if logdev.respond_to?(:write) and logdev.respond_to?(:close)
        # IO
        @logdev = logdev
        @logdev.sync = true if @logdev.respond_to?(:sync=)
        if @file_dev
          old_file_dev = @file_dev
          @file_dev = nil
          old_file_dev.close
        end
      elsif !@file_dev || @file_dev.filename != logdev
        # update path string
        old_file_dev = @file_dev
        @file_dev = @logdev_class.new(logdev, shift_age: @rotate_age, shift_size: @rotate_size)
        old_file_dev.close if old_file_dev
        @logdev = @file_dev
      end
      logdev
    end

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
      @file_dev.reopen! if @file_dev
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
      @file_dev.close if @file_dev
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

      def reopen!
        @mutex.synchronize do
          if @file
            @file.reopen(@path, 'a')
            @file.sync = true
          end
        end
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
        retry_limit = 8
        retry_sleep = 0.1
        begin
          # 1) other process is log-rotating now
          # 2) other process log rotated
          # 3) no active processes
          lock = File.open(@path, File::WRONLY | File::APPEND)
          begin
            lock.flock(File::LOCK_EX)
            ino = lock.stat.ino
            if ino == File.stat(@path).ino and ino == stat.ino
              # 3)
              log_rotate
            else
              @file.reopen(@path, 'a')
              @file.sync = true
            end
          ensure
            lock.close
          end
        rescue Errno::ENOENT => e
          raise e if retry_limit <= 0
          sleep retry_sleep
          retry_limit -= 1
          retry_sleep *= 2
          retry
        end

      rescue => e
        warn "log rotation inter-process lock failed: #{e}"
      end

      def log_rotate
        (@shift_age-2).downto(0) do |i|
          old_path = "#{@path}.#{i}"
          shift_path = "#{@path}.#{i+1}"
          if FileTest.exist?(old_path)
            File.rename(old_path, shift_path)
          end
        end
        File.rename(@path, "#{@path}.0")
        @file.reopen(@path, 'a')
        @file.sync = true
      rescue => e
        warn "log rotation failed: #{e}"
      end
    end
  end

end
