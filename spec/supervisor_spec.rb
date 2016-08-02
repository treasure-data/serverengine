
describe ServerEngine::Supervisor do
  include_context 'test server and worker'

  def start_supervisor(worker = nil, config={})
    if ServerEngine.windows?
      config[:windows_daemon_cmdline] = windows_supervisor_cmdline(nil, worker, config)
      config[:command_sender] = "pipe"
    end
    sv = Supervisor.new(TestServer, worker || TestWorker, config)
    t = Thread.new { sv.main }

    return sv, t
  end

  def start_daemon(config={})
    if ServerEngine.windows?
      config[:windows_daemon_cmdline] = windows_daemon_cmdline
      config[:command_sender] = "pipe"
    end
    daemon = Daemon.new(nil, TestWorker, config)
    t = Thread.new { daemon.main }

    return daemon, t
  end

  context 'when :log=IO option is given' do
    it 'can start' do
      daemon, t = start_daemon(log: STDOUT)

      begin
        wait_for_fork
      ensure
        daemon.server.stop(true)
        t.join
      end

      test_state(:worker_run).should == 1
      daemon.server.logger.should be_an_instance_of(ServerEngine::DaemonLogger)
    end
  end

  context 'when :logger option is given' do
    it 'uses specified logger instance' do
      logger = ServerEngine::DaemonLogger.new(STDOUT)
      daemon, t = start_daemon(logger: logger)

      begin
        wait_for_fork
      ensure
        daemon.server.stop(true)
        t.join
      end

      test_state(:worker_run).should == 1
      daemon.server.logger.should == logger
    end
  end

  context 'when both :logger and :log options are given' do
    it 'start ignoring :log' do
      logger = ServerEngine::DaemonLogger.new(STDOUT)
      daemon, t = start_daemon(logger: logger, log: STDERR)

      begin
        wait_for_fork
      ensure
        daemon.server.stop(true)
        t.join
      end

      test_state(:worker_run).should == 1
      daemon.server.logger.should == logger
    end
  end

  it 'start and graceful stop' do
    sv, t = start_supervisor

    begin
      wait_for_fork

      test_state(:server_before_run).should == 1
      test_state(:server_after_start).should == 1  # parent
    ensure
      sv.stop(true)
      t.join
    end

    test_state(:server_stop).should == 1
    test_state(:server_stop_graceful).should == 1
    test_state(:server_restart).should == 0

    test_state(:server_after_run).should == 1
    test_state(:server_after_start).should == 1
  end

  it 'immediate stop' do
    sv, t = start_supervisor

    begin
      wait_for_fork
    ensure
      sv.stop(false)
      t.join
    end

    test_state(:server_stop).should == 1
    test_state(:server_stop_immediate).should == 1
    test_state(:server_after_run).should == 1
    test_state(:server_after_start).should == 1
  end

  it 'graceful restart' do
    sv, t = start_supervisor

    begin
      wait_for_fork

      sv.restart(true)
      wait_for_stop

    ensure
      sv.stop(true)
      t.join
    end

    test_state(:server_stop).should == 1
    test_state(:server_restart_graceful).should == 1

    test_state(:server_before_run).should == 1
    test_state(:server_after_run).should == 1
    test_state(:server_after_start).should == 1
  end

  it 'immediate restart' do
    sv, t = start_supervisor

    begin
      wait_for_fork

      sv.restart(false)
      wait_for_stop

    ensure
      sv.stop(true)
      t.join
    end

    test_state(:server_stop).should == 1
    test_state(:server_restart_immediate).should == 1

    test_state(:server_before_run).should == 1
    test_state(:server_after_run).should == 1
    test_state(:server_after_start).should == 1
  end

  it 'reload' do
    sv, t = start_supervisor

    begin
      wait_for_fork

      sv.reload

    ensure
      sv.stop(true)
      t.join
    end

    test_state(:server_stop).should == 1
    test_state(:server_reload).should == 1
  end

  # TODO detach

  module InitializeErrorServer
    def initialize
      raise StandardError, "error test"
    end
  end

  it 'initialize error' do
    sv = Supervisor.new(InitializeErrorServer, TestWorker)
    lambda { sv.main }.should raise_error(StandardError)
  end

  it 'auto restart in limited ratio' do
    sv, t = start_supervisor(RunErrorWorker, server_restart_wait: 1)

    begin
      sleep 2.2
    ensure
      sv.stop(true)
      t.join
    end

    test_state(:worker_run).should == 3
  end

end
