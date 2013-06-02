
describe ServerEngine::Daemon do
  include_context 'test server and worker'

  it 'run and graceful stop' do
    dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid")
    dm.main

    test_state(:server_initialize).should == 1

    pid = File.read('tmp/pid').to_i
    wait_for_fork

    Process.kill(:TERM, pid)
    wait_for_stop

    test_state(:server_stop_graceful).should == 1
    test_state(:worker_stop).should == 1
    test_state(:server_after_run).should == 1
  end

  it 'signals' do
    dm = Daemon.new(TestServer, TestWorker, daemonize: true, pid_path: "tmp/pid")
    dm.main

    pid = File.read('tmp/pid').to_i
    wait_for_fork

    Process.kill(:USR2, pid)
    wait_for_stop
    test_state(:server_reload).should == 1

    Process.kill(:USR1, pid)
    wait_for_stop
    test_state(:server_restart_graceful).should == 1

    Process.kill(:HUP, pid)
    wait_for_stop
    test_state(:server_restart_immediate).should == 1

    Process.kill(:QUIT, pid)
    wait_for_stop
    test_state(:server_stop_immediate).should == 1
  end
end

