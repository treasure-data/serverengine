
describe ServerEngine::Daemon do
  include_context 'test server and worker'

  it 'run and graceful stop by signal' do
    pending "not supported signal base commands on Windows" if ServerEngine.windows?

    dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid", command_sender: "signal")
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
    pending "not supported signal base commands on Windows" if ServerEngine.windows?
    dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid", command_sender: "signal")
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

      dm.dump
      wait_for_stop
      test_state(:server_dump).should == 1

      dm.stop(false)
      wait_for_stop
      test_state(:server_stop_immediate).should == 1
    ensure
      dm.stop(true) rescue nil
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

  it 'exits with status 0 when it was stopped normally' do
    pending "worker type process(fork) cannot be used in Windows" if ServerEngine.windows?
    dm = Daemon.new(
      TestServer,
      TestWorker,
      daemonize: false,
      supervisor: false,
      pid_path: "tmp/pid",
      log_stdout: false,
      log_stderr: false,
      unrecoverable_exit_codes: [3,4,5],
    )
    exit_code = nil
    t = Thread.new { exit_code = dm.main }
    sleep 0.1 until dm.instance_eval{ @pid }
    dm.stop(true)

    t.join

    exit_code.should == 0
  end

  it 'exits with status of workers if worker exits with status specified in unrecoverable_exit_codes, without supervisor' do
    pending "worker type process(fork) cannot be used in Windows" if ServerEngine.windows?

    dm = Daemon.new(
      TestServer,
      TestExitWorker,
      daemonize: false,
      supervisor: false,
      worker_type: 'process',
      pid_path: "tmp/pid",
      log_stdout: false,
      log_stderr: false,
      unrecoverable_exit_codes: [3,4,5],
    )
    exit_code = nil
    t = Thread.new { exit_code = dm.main }
    sleep 0.1 until dm.instance_eval{ @pid }

    t.join

    exit_code.should == 5
  end

  it 'exits with status of workers if worker exits with status specified in unrecoverable_exit_codes, with supervisor' do
    pending "worker type process(fork) cannot be used in Windows" if ServerEngine.windows?

    dm = Daemon.new(
      TestServer,
      TestExitWorker,
      daemonize: false,
      supervisor: true,
      worker_type: 'process',
      pid_path: "tmp/pid",
      log_stdout: false,
      log_stderr: false,
      unrecoverable_exit_codes: [3,4,5],
    )
    exit_code = nil
    t = Thread.new { exit_code = dm.main }
    sleep 0.1 until dm.instance_eval{ @pid }

    t.join

    exit_code.should == 5
  end
end
