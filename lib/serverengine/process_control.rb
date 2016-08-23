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
require 'serverengine/signals'

module ServerEngine
  module ProcessControl
    def self.sender_class(type)
      case type || (ServerEngine.windows? ? "pipe" : "signal")
      when "signal"
        return ProcessControl::SignalSender
      when "pipe"
        return ProcessControl::PipeSender
      else
        raise ArgumentError, "unexpected :process_control_type option #{process_control_type}"
      end
    end

    def self.new_sender(type, opts={})
      return sender_class(type).new(opts)
    end

    def self.process_monitor_kill_handler(signal_sender)
      lambda do |type, pmon|
        case type
        when :force
          pmon.send_signal(:KILL)
        when :graceful
          signal_sender.stop(true)
        when :immediate
          signal_sender.stop(false)
        end
      end
    end

    class SignalSender
      def initialize(opts={}, attach_process_monitor=nil)
        if attach_process_monitor
          attach(attach_process_monitor)
        end
        @signals = Signals.mapping({}).merge(opts)
      end

      attr_accessor :pid

      def pipe
      end

      def attach(process_monitor)
        @process_monitor = process_monitor
        @pid = process_monitor.pid
        process_monitor.kill_handler = ProcessControl.process_monitor_kill_handler(self)
        nil
      end

      def close
      end

      def stop(graceful)
        send_signal(graceful ? @signals[:graceful_stop] : @signals[:immediate_stop])
      end

      def restart(graceful)
        send_signal(graceful ? @signals[:graceful_restart] : @signals[:immediate_restart])
      end

      def reload
        send_signal(@signals[:reload])
      end

      def detach
        send_signal(@signals[:detach])
      end

      def dump
        send_signal(@signals[:dump])
      end

      private

      def send_signal(sig)
        if @process_monitor
          @process_monitor.send_signal(sig)
        elsif @pid
          ServerEngine.kill(sig, @pid)  # TODO logger is not available here...
        end
      end
    end

    class Commands
      GRACEFUL_STOP = "GRACEFUL_STOP"
      IMMEDIATE_STOP = "IMMEDIATE_STOP"
      GRACEFUL_RESTART = "GRACEFUL_RESTART"
      IMMEDIATE_RESTART = "IMMEDIATE_RESTART"
      RELOAD = "RELOAD"
      DETACH = "DETACH"
      DUMP = "DUMP"
    end

    class PipeSender
      def initialize(opts={}, process_monitor=nil)
        if process_monitor
          unless process_monitor.hooked_stdin
            raise ArgumentError, "ProcessControl.new_sender requires a process monitor created by a ProcessManager with hook_stdin option enabled"
          end
          @send_pipe = process_monitor.hooked_stdin
          attach(process_monitor)
        end
      end

      attr_accessor :pid

      def pipe
        subproc_control_pipe, @send_pipe = IO.pipe
        @send_pipe.sync = true
        @send_pipe.binmode
        return subproc_control_pipe
      end

      def attach(process_monitor)
        process_monitor.kill_handler = ProcessControl.process_monitor_kill_handler(self)
        nil
      end

      def close
        if @send_pipe
          @send_pipe.close rescue nil
          @send_pipe = nil
        end
      end

      def stop(graceful)
        begin
          send_command(graceful ? Commands::GRACEFUL_STOP : Commands::IMMEDIATE_STOP)
        rescue Errno::EPIPE
          # already stopped, then nothing to do
        ensure
          @send_pipe.close rescue nil
          @send_pipe = nil
        end
      end

      def restart(graceful)
        send_command(graceful ? Commands::GRACEFUL_RESTART : Commands::IMMEDIATE_RESTART)
      end

      def reload
        send_command(Commands::RELOAD)
      end

      def detach
        send_command(Commands::DETACH)
      end

      def dump
        send_command(Commands::DUMP)
      end

      private

      def send_command(cmd)
        if @send_pipe
          @send_pipe.write cmd + "\n"
        end
      end
    end

    class PipeReceiver
      def initialize(pipe)
        @pipe = pipe
      end

      def closed?
        @pipe.closed?
      end

      def each
        until closed?
          self.next
        end
      end

      def next
        @pipe.gets.chomp
      end

      def close
        unless @pipe.closed?
          @pipe.close
        end
      end
    end
  end
end
