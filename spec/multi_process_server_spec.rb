[ServerEngine::MultiThreadServer, ServerEngine::MultiProcessServer].each do |impl_class|
  # MultiProcessServer uses fork(2) internally, then it doesn't support Windows.

  describe impl_class do
    include_context 'test server and worker'

    it 'scale up' do
      pending "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {workers: 2, log_stdout: false, log_stderr: false}

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
      pending "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {workers: 2, log_stdout: false, log_stderr: false}

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

    it 'raises SystemExit when all workers exit with specified code by unrecoverable_exit_codes' do
      pending "unrecoverable_exit_codes supported only for multi process workers" if impl_class == ServerEngine::MultiThreadServer
      pending "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {workers: 4, log_stdout: false, log_stderr: false, unrecoverable_exit_codes: [3, 4, 5]}

      s = impl_class.new(TestExitWorker) { config.dup }
      raised_error = nil
      t = Thread.new do
        begin
          s.main
        rescue SystemExit => e
          raised_error = e
        end
      end

      wait_for_fork
      test_state(:worker_run).should == 4
      t.join

      test_state(:worker_stop).to_i.should == 0
      raised_error.status.should == 3 # 4th process's exit status
    end

    it 'raises SystemExit immediately when a worker exits if stop_immediately_at_unrecoverable_exit specified' do
      pending "unrecoverable_exit_codes supported only for multi process workers" if impl_class == ServerEngine::MultiThreadServer
      pending "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {workers: 4, log_stdout: false, log_stderr: false, unrecoverable_exit_codes: [3, 4, 5], stop_immediately_at_unrecoverable_exit: true}

      s = impl_class.new(TestExitWorker) { config.dup }
      raised_error = nil
      t = Thread.new do
        begin
          s.main
        rescue SystemExit => e
          raised_error = e
        end
      end

      wait_for_fork
      test_state(:worker_run).should == 4
      t.join

      test_state(:worker_stop).to_i.should == 3
      test_state(:worker_finished).to_i.should == 3
      raised_error.should_not be_nil
      raised_error.status.should == 5 # 1st process's exit status
    end
  end
end
