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
        @create_server_proc = lambda do |_load_config_proc,logger|
          s = Supervisor.new(server_module, worker_module, _load_config_proc)
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

      @pid = nil
      extend ServerEngine::CommandSender::Signal
    end

    # server is available when run() is called. It is a Supervisor instance if supervisor is set to true. Otherwise a Server instance.
    attr_reader :server

    module Signals
      GRACEFUL_STOP = :TERM
      IMMEDIATE_STOP = ServerEngine::windows? ? :KILL : :QUIT
      GRACEFUL_RESTART = :USR1
      IMMEDIATE_RESTART = :HUP
      RELOAD = :USR2
      DETACH = :INT
      DUMP = :CONT
    end

    def self.get_etc_passwd(user)
      if user.to_i.to_s == user
        Etc.getpwuid(user.to_i)
      else
        Etc.getpwnam(user)
      end
    end

    def self.get_etc_group(group)
      if group.to_i.to_s == group
        Etc.getgrgid(group.to_i)
      else
        Etc.getgrnam(group)
      end
    end

    def self.change_privilege(user, group)
      if user
        etc_pw = Daemon.get_etc_passwd(user)
        user_groups = [etc_pw.gid]
        Etc.setgrent
        Etc.group { |gr| user_groups << gr.gid if gr.mem.include?(etc_pw.name) } # emulate 'id -G'

        Process.groups = Process.groups | user_groups
        Process::UID.change_privilege(etc_pw.uid)
      end

      if group
        etc_group = Daemon.get_etc_group(group)
        Process::GID.change_privilege(etc_group.gid)
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

    def self.run_server(server_module, worker_module, load_config_proc={}, &block)
      Daemon.new(server_module, worker_module, load_config_proc, &block).server_main
    end

    def server_main
      $0 = @daemon_process_name if @daemon_process_name

      Daemon.change_privilege(@chuser, @chgroup)
      File.umask(@chumask) if @chumask

      s = create_server(create_logger)

      STDIN.reopen(File::NULL)
      STDOUT.reopen(File::NULL, "wb")
      STDERR.reopen(File::NULL, "wb")

      s.install_signal_handlers

      s.main
    end

    def main
      unless @daemonize
        @pid = Process.pid
        s = create_server(create_logger)
        s.install_signal_handlers
        s.main
        return 0
      end

      rpipe, wpipe = IO.pipe
      wpipe.sync = true

      if ServerEngine.windows?
        windows_daemon_cmdline = config[:windows_daemon_cmdline]
        @pid = Process.spawn(*Array(windows_daemon_cmdline))
        wpipe.close
      else
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

        @pid = rpipe.gets.to_i
      end

      if @pid_path
        File.open(@pid_path, "w") {|f|
          f.write "#{@pid}\n"
        }
      end

      unless ServerEngine.windows?
        data = rpipe.read
        rpipe.close
        if data != "\n"
          return @daemonize_error_exit_code
        end
      end
      rpipe.close

      return 0
    end

    private

    def create_server(logger)
      @server = @create_server_proc.call(@load_config_proc, logger)
    end
  end
end
