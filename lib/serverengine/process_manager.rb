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
require 'fcntl'
require 'serverengine/signals'
require 'serverengine/utils'

module ServerEngine

  class ProcessManager
    def initialize(config={})
      @monitors = []
      @rpipes = {}
      @heartbeat_time = {}

      @cloexec_mode = config[:cloexec_mode]

      @graceful_kill_signal = config[:graceful_kill_signal] || Signals::GRACEFUL_STOP
      @immediate_kill_signal = config[:immediate_kill_signal] || Signals::IMMEDIATE_STOP

      @auto_tick = !!config.fetch(:auto_tick, true)
      @auto_tick_interval = config[:auto_tick_interval] || 1

      @enable_heartbeat = !!config[:enable_heartbeat]
      if ServerEngine.windows?
        # heartbeat is not supported on Windows platform. See also spawn method.
        @enable_heartbeat = false
      end
      @auto_heartbeat = !!config.fetch(:auto_heartbeat, true)

      case op = config[:on_heartbeat_error]
      when nil
        @heartbeat_error_proc = lambda {|t| }
      when Proc
        @heartbeat_error_proc = op
      when :abort
        @heartbeat_error_proc = lambda {|t| exit 1 }
      else
        raise ArgumentError, "unexpected :on_heartbeat_error option (expected Proc, true or false but got #{op.class})"
      end

      configure(config)

      @closed = false
      @read_buffer = ''

      if @auto_tick
        TickThread.new(@auto_tick_interval, &method(:tick))
      end
    end

    attr_accessor :logger

    attr_accessor :cloexec_mode

    attr_accessor :graceful_kill_signal, :immediate_kill_signal

    attr_reader :auto_tick, :auto_tick_interval
    attr_reader :enable_heartbeat, :auto_heartbeat

    attr_accessor :hook_stdin

    CONFIG_PARAMS = {
      heartbeat_interval: 1,
      heartbeat_timeout: 180,
      graceful_kill_interval: 15,
      graceful_kill_interval_increment: 10,
      graceful_kill_timeout: 600,
      immediate_kill_interval: 10,
      immediate_kill_interval_increment: 10,
      immediate_kill_timeout: 600,
    }

    CONFIG_PARAMS.each_pair do |key,default_value|
      attr_reader key

      define_method("#{key}=") do |v|
        v = default_value if v == nil
        instance_variable_set("@#{key}", v)
      end
    end

    def configure(config, opts={})
      prefix = opts[:prefix] || ""
      CONFIG_PARAMS.keys.each {|key|
        send("#{key}=", config[:"#{prefix}#{key}"])
      }
    end

    def monitor_options
      {
        logger: @logger,
        enable_heartbeat: @enable_heartbeat,
        heartbeat_timeout: @heartbeat_timeout,
        graceful_kill_signal: @graceful_kill_signal,
        graceful_kill_timeout: @graceful_kill_timeout,
        graceful_kill_interval: @graceful_kill_interval,
        graceful_kill_interval_increment: @graceful_kill_interval_increment,
        immediate_kill_signal: @immediate_kill_signal,
        immediate_kill_timeout: @immediate_kill_timeout,
        immediate_kill_interval: @immediate_kill_interval,
        immediate_kill_interval_increment: @immediate_kill_interval_increment,
      }
    end

    def fork(&block)
      if ServerEngine.windows?
        raise NotImplementedError, "fork is not available on this platform. Please use spawn (worker_type: 'spawn')."
      end

      rpipe, wpipe = new_pipe_pair

      if @hook_stdin
        stdin_rpipe, stdin_wpipe = new_pipe_pair
      end

      begin
        pid = Process.fork do
          self.close
          stdin_wpipe.close if stdin_wpipe
          begin
            t = Target.new(wpipe)
            if @enable_heartbeat && @auto_heartbeat
              HeartbeatThread.new(@heartbeat_interval, t, @heartbeat_error_proc)
            end

            STDIN.reopen(stdin_rpipe) if stdin_rpipe

            block.call(t)
            exit! 0

          rescue
            ServerEngine.dump_uncaught_error($!)
          ensure
            exit! 1
          end
        end

        m = Monitor.new(pid, monitor_options.merge({
          hooked_stdin: stdin_wpipe,
        }))

        @monitors << m
        @rpipes[rpipe] = m
        rpipe = nil

        return m

      ensure
        wpipe.close
        rpipe.close if rpipe
        stdin_rpipe if stdin_rpipe
      end
    end

    def spawn(*args)
      if args.first.is_a?(Hash)
        env = args.shift.dup
      else
        env = {}
      end

      if args.last.is_a?(Hash)
        options = args.pop.dup
      else
        options = {}
      end

      if @hook_stdin
        stdin_rpipe, stdin_wpipe = new_pipe_pair
        options[:in] = stdin_rpipe
      end

      # pipe is necessary even if @enable_heartbeat == false because
      # parent process detects shutdown of a child process using it
      begin
        unless ServerEngine.windows?
          # heartbeat is not supported on Windows platform
          rpipe, wpipe = new_pipe_pair
          options[[wpipe.fileno]] = wpipe
          if @enable_heartbeat
            env['SERVERENGINE_HEARTBEAT_PIPE'] = wpipe.fileno.to_s
          end
        end

        pid = Process.spawn(env, *args, options)

        m = Monitor.new(pid, monitor_options.merge({
          hooked_stdin: stdin_wpipe,
        }))

        if stdin_wpipe
          stdin_wpipe.sync = true
          stdin_wpipe.binmode
        end

        @monitors << m

        unless ServerEngine.windows?
          @rpipes[rpipe] = m
          rpipe = nil
        end

        return m

      ensure
        wpipe.close if wpipe
        rpipe.close if rpipe
        stdin_rpipe.close if stdin_rpipe
      end
    end

    def new_pipe_pair
      rpipe, wpipe = IO.pipe

      if Fcntl.const_defined?(:F_SETFD) && Fcntl.const_defined?(:FD_CLOEXEC)
        case @cloexec_mode
        when :target_only
          wpipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        when :monitor_only
          rpipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        else
          rpipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
          wpipe.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        end
      end

      rpipe.sync = true
      wpipe.sync = true

      return rpipe, wpipe
    end

    def close
      @closed = true
      @rpipes.keys.each {|m| m.close }
      nil
    end

    def tick(blocking_timeout=0)
      if @closed
        raise AlreadyClosedError.new
      end

      time ||= Time.now

      unless ServerEngine.windows?
        # heartbeat is not supported on Windows platform.

        if @rpipes.empty?
          sleep blocking_timeout if blocking_timeout > 0
          return nil
        end

        ready_pipes, _, _ = IO.select(@rpipes.keys, nil, nil, blocking_timeout)

        if ready_pipes
          ready_pipes.each do |r|
            begin
              r.read_nonblock(1024, @read_buffer)
            rescue Errno::EAGAIN, Errno::EINTR
              next
            rescue #EOFError
              m = @rpipes.delete(r)
              m.start_immediate_stop!
              r.close rescue nil
              next
            end

            if m = @rpipes[r]
              m.last_heartbeat_time = time
            end
          end
        end
      end

      @monitors.delete_if {|m|
        !m.tick(time)
      }

      nil
    end

    class AlreadyClosedError < EOFError
    end

    HEARTBEAT_MESSAGE = [0].pack('C')

    class Monitor
      def initialize(pid, opts={})
        @pid = pid

        @logger = opts[:logger]
        @hooked_stdin = opts[:hooked_stdin]

        @enable_heartbeat = opts[:enable_heartbeat]
        @heartbeat_timeout = opts[:heartbeat_timeout]

        @graceful_kill_signal   = opts[:graceful_kill_signal]
        @graceful_kill_timeout  = opts[:graceful_kill_timeout]
        @graceful_kill_interval = opts[:graceful_kill_interval]
        @graceful_kill_interval_increment = opts[:graceful_kill_interval_increment]

        @immediate_kill_signal   = opts[:immediate_kill_signal]
        @immediate_kill_timeout  = opts[:immediate_kill_timeout]
        @immediate_kill_interval = opts[:immediate_kill_interval]
        @immediate_kill_interval_increment = opts[:immediate_kill_interval_increment]

        @error = false
        @last_heartbeat_time = Time.now
        @next_kill_time = nil
        @graceful_kill_start_time = nil
        @immediate_kill_start_time = nil
        @kill_count = 0
      end

      attr_accessor :kill_handler
      attr_accessor :logger

      attr_accessor :last_heartbeat_time
      attr_reader :pid

      attr_reader :hooked_stdin

      def heartbeat_delay
        now = Time.now
        now - @last_heartbeat_time
      end

      def kill(type)
        if @kill_handler
          alive = @kill_handler.call(type, self)

        else
          case type
          when :force
            signal = :KILL
          when :graceful
            signal = @graceful_kill_signal
          when :immediate
            signal = @immediate_kill_signal
          end
          alive = send_signal(signal)
        end

        return alive
      end

      def send_signal(signal)
        pid = @pid
        return nil unless pid

        return ServerEngine.kill(signal, pid, @logger)
      end

      def try_join
        pid = @pid
        return true unless pid

        begin
          pid, status = Process.waitpid2(pid, Process::WNOHANG)
          code = status
        rescue #Errno::ECHILD, Errno::ESRCH, Errno::EPERM
          # assume that any errors mean the child process is dead
          code = $!
        end

        if code
          @hooked_stdin.close if @hooked_stdin
          @pid = nil
          return code
        end

        return false
      end

      def join
        pid = @pid
        return nil unless pid

        begin
          pid, status = Process.waitpid2(pid)
          code = status
        rescue #Errno::ECHILD, Errno::ESRCH, Errno::EPERM
          # assume that any errors mean the child process is dead
          code = $!
        end
        @hooked_stdin.close if @hooked_stdin
        @pid = nil

        return code
      end

      def start_graceful_stop!
        now = Time.now
        @next_kill_time ||= now
        @graceful_kill_start_time ||= now
      end

      def start_immediate_stop!
        now = Time.now
        @next_kill_time ||= now
        @immediate_kill_start_time ||= now
      end

      def tick(now=Time.now)
        return false unless @pid

        if !@immediate_kill_start_time
          # check heartbeat timeout or escalation
          if (
              # heartbeat timeout
              @enable_heartbeat &&
              heartbeat_delay >= @heartbeat_timeout
             ) || (
               # escalation
               @graceful_kill_start_time &&
               @graceful_kill_timeout >= 0 &&
               @graceful_kill_start_time < now - @graceful_kill_timeout
             )
            # escalate to immediate kill
            @kill_count = 0
            @immediate_kill_start_time = now
            @next_kill_time = now
          end
        end

        if !@next_kill_time || @next_kill_time > now
          # expect next tick
          return true
        end

        # send signal now

        if @immediate_kill_start_time
          interval = @immediate_kill_interval
          interval_incr = @immediate_kill_interval_increment
          if @immediate_kill_timeout >= 0 &&
              @immediate_kill_start_time <= now - @immediate_kill_timeout
            # escalate to SIGKILL
            type = :force
          else
            type = :immediate
          end

        else
          type = :graceful
          interval = @graceful_kill_interval
          interval_incr = @graceful_kill_interval_increment
        end

        alive = kill(type)
        unless alive
          @hooked_stdin.close if @hooked_stdin
          @pid = nil
          return false
        end

        @next_kill_time = now + interval + interval_incr * @kill_count
        @kill_count += 1

        # expect next tick
        return true
      end
    end

    class TickThread < Thread
      def initialize(auto_tick_interval, &tick)
        @auto_tick_interval = auto_tick_interval
        @tick = tick
        super(&method(:main))
      end

      private

      def main
        while true
          @tick.call(@auto_tick_interval)
        end
        nil
      rescue AlreadyClosedError
        nil
      end
    end

    class Target
      def initialize(pipe)
        @pipe = pipe
      end

      attr_reader :pipe

      def heartbeat!
        @pipe.write HEARTBEAT_MESSAGE
      end

      def close
        if @pipe
          @pipe.close rescue nil
          @pipe = nil
        end
      end
    end

    class HeartbeatThread < Thread
      def initialize(heartbeat_interval, target, error_proc)
        @heartbeat_interval = heartbeat_interval
        @target = target
        @error_proc = error_proc
        super(&method(:main))
      end

      private

      def main
        while true
          sleep @heartbeat_interval
          @target.heartbeat!
        end
        nil
      rescue
        @error_proc.call(self)
        nil
      end
    end

  end

end
