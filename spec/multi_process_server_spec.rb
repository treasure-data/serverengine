
describe ServerEngine::MultiWorkerServer do
  include_context 'test server and worker'

  [MultiThreadServer, MultiProcessServer].each do |impl_class|

    it 'scale up' do
      config = {:workers => 2}

      s = impl_class.new(TestWorker) { config.dup }
      t = Thread.new { s.main }

      begin
        wait_for_fork
        test_state(:worker_run).should == 2

        config[:workers] = 3
        s.reload

        wait_for_restart
        test_state(:worker_run).should == 3

        test_state(:worker_stop).should == 0

      ensure
        s.stop(true)
        t.join
      end

      test_state(:worker_stop).should == 3
    end

    it 'scale down' do
      config = {:workers => 2}

      s = impl_class.new(TestWorker) { config.dup }
      t = Thread.new { s.main }

      begin
        wait_for_fork
        test_state(:worker_run).should == 2

        config[:workers] = 1
        s.restart(true)

        wait_for_restart
        test_state(:worker_run).should == 3

        test_state(:worker_stop).should == 2

      ensure
        s.stop(true)
        t.join
      end

      test_state(:worker_stop).should == 3
    end

  end
end

