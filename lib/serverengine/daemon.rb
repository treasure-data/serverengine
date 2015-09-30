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
module ServerEngine

  require 'shellwords'

  class Daemon
    include ConfigLoader

    def initialize(server_module, worker_module, load_config_proc={}, &block)
      @server_module = server_module
      @worker_module = worker_module

      super(load_config_proc, &block)

      @daemonize = @config.fetch(:daemonize, false)

      if @config.fetch(:supervisor, false)
        @create_server_proc = lambda do |load_config_proc,logger|
          s = Supervisor.new(server_module, worker_module, load_config_proc)
          s.logger = logger
          s
        end
      else
        @create_server_proc = Supervisor.create_server_proc(server_module, worker_module, @config)
      end

      @daemon_process_name = @config[:daemon_process_name]
      @daemonize_error_exit_code = @config[:daemonize_error_exit_code] || 1

      @pid_path = @config[:pid_path]
      @chuser = @config[:chuser]
      @chgroup = @config[:chgroup]
      @chumask = @config[:chumask]
    end

    module Signals
      GRACEFUL_STOP = :TERM
      IMMEDIATE_STOP = :QUIT
      GRACEFUL_RESTART = :USR1
      IMMEDIATE_RESTART = :HUP
      RELOAD = :USR2
      DETACH = :INT
      DUMP = :CONT
    end

    def self.change_privilege(user, group)
      if group
        chgid = group.to_i
        if chgid.to_s != group
          chgid = Process::GID.from_name(group)
        end
        Process::GID.change_privilege(chgid)
      end

      if user
        chuid = user.to_i
        if chuid.to_s != user
          chuid = Process::UID.from_name(user)
        end

        user_groups = `id -G #{Shellwords.escape user}`.split.map(&:to_i)
        if $?.success?
          Process.groups = Process.groups | user_groups
        end

        Process::UID.change_privilege(chuid)
      end

      nil
    end

    def run
      begin
        exit main
      rescue => e
        ServerEngine.dump_uncaught_error(e)
        exit @daemonize_error_exit_code
      end
    end

    def main
      unless @daemonize
        s = create_server(create_logger)
        s.install_signal_handlers
        s.main
        return 0
      end

      rpipe, wpipe = IO.pipe
      wpipe.sync = true

      Process.fork do
        begin
          rpipe.close

          Process.setsid
          Process.fork do
            $0 = @daemon_process_name if @daemon_process_name
            wpipe.write "#{Process.pid}\n"

            Daemon.change_privilege(@chuser, @chgroup)
            File.umask(@chumask) if @chumask

            s = create_server(create_logger)

            STDIN.reopen(File::NULL)
            STDOUT.reopen(File::NULL, "wb")
            STDERR.reopen(File::NULL, "wb")

            s.install_signal_handlers

            wpipe.write "\n"
            wpipe.close

            s.main
          end

          exit 0
        ensure
          exit! @daemonize_error_exit_code
        end
      end

      wpipe.close

      pid = rpipe.gets.to_i
      if @pid_path
        File.open(@pid_path, "w") {|f|
          f.write "#{pid}\n"
        }
      end

      data = rpipe.read
      if data != "\n"
        return @daemonize_error_exit_code
      end

      return 0
    end

    private

    def create_server(logger)
      @create_server_proc.call(@load_config_proc, logger)
    end
  end
end
