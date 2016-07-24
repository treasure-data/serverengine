
describe ServerEngine::Daemon do
  include_context 'test server and worker'

  unless ServerEngine.windows?
    it 'run and graceful stop by signal' do
      dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid")
      dm.main

      wait_for_fork

      test_state(:server_initialize).should == 1

      begin
        dm.stop(true)
        wait_for_stop

        test_state(:server_stop_graceful).should == 1
        test_state(:worker_stop).should == 1
        test_state(:server_after_run).should == 1
      ensure
        dm.stop(false) rescue nil
      end
    end

    it 'signals' do
      dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid")
      dm.main

      wait_for_fork

      begin
        dm.reload
        wait_for_stop
        test_state(:server_reload).should == 1

        dm.restart(true)
        wait_for_stop
        test_state(:server_restart_graceful).should == 1

        dm.restart(false)
        wait_for_stop
        test_state(:server_restart_immediate).should == 1

        dm.stop(false)
        wait_for_stop
        test_state(:server_stop_immediate).should == 1
      ensure
        dm.stop(true) rescue nil
      end
    end
  end

  it 'run and graceful stop by pipe' do
    dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid", windows_daemon_cmdline: windows_daemon_cmdline, command_sender: "pipe")
    dm.main

    wait_for_fork

    test_state(:server_initialize).should == 1

    begin
      dm.stop(true)
      wait_for_stop

      test_state(:server_stop_graceful).should == 1
      test_state(:worker_stop).should == 1
      test_state(:server_after_run).should == 1
    ensure
      dm.stop(false) rescue nil
    end
  end

  it 'recieve commands from pipe' do
    dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid", windows_daemon_cmdline: windows_daemon_cmdline, command_sender: "pipe")
    dm.main

    wait_for_fork

    begin
      dm.reload
      wait_for_stop
      test_state(:server_reload).should == 1

      dm.restart(true)
      wait_for_stop
      test_state(:server_restart_graceful).should == 1

      dm.restart(false)
      wait_for_stop
      test_state(:server_restart_immediate).should == 1

      dm.stop(false)
      wait_for_stop
      test_state(:server_stop_immediate).should == 1
    ensure
      dm.stop(true) rescue nil
    end
  end
end
