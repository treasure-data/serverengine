
describe ServerEngine::Supervisor do
  include_context 'test server and worker'

  def start_supervisor(config={})
    sv = Supervisor.new(TestServer, TestWorker, config)
    t = Thread.new { sv.main }

    return sv, t
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

  module RunErrorWorker
    def run
      incr_test_state :worker_run
      raise StandardError, "error test"
    end
  end

  it 'auto restart in limited ratio' do
    sv = Supervisor.new(TestServer, RunErrorWorker, server_restart_wait: 1)
    t = Thread.new { sv.main }

    begin
      sleep 2.2
    ensure
      sv.stop(true)
      t.join
    end

    test_state(:worker_run).should == 3
  end

end
