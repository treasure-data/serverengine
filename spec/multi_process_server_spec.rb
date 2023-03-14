require 'timeout'
require 'securerandom'

[ServerEngine::MultiThreadServer, ServerEngine::MultiProcessServer].each do |impl_class|
  # MultiProcessServer uses fork(2) internally, then it doesn't support Windows.

  describe impl_class do
    include_context 'test server and worker'

    before do
      @log_path = "tmp/multi-worker-test-#{SecureRandom.hex(10)}.log"
      @logger = ServerEngine::DaemonLogger.new(@log_path)
    end

    after do
      FileUtils.rm_rf(@log_path)
    end

    it 'scale up' do
      skip "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {
        workers: 2,
        logger: @logger,
        log_stdout: false,
        log_stderr: false,
      }

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
      skip "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {
        workers: 2,
        logger: @logger,
        log_stdout: false,
        log_stderr: false
      }

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

[ServerEngine::MultiProcessServer].each do |impl_class|
  describe impl_class do
    include_context 'test server and worker'

    before do
      @log_path = "tmp/multi-worker-test-#{SecureRandom.hex(10)}.log"
      @logger = ServerEngine::DaemonLogger.new(@log_path)
    end

    after do
      FileUtils.rm_rf(@log_path)
    end

    it 'raises SystemExit when all workers exit with specified code by unrecoverable_exit_codes' do
      skip "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {
        workers: 4,
        logger: @logger,
        log_stdout: false,
        log_stderr: false,
        unrecoverable_exit_codes: [3, 4, 5]
      }

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
      skip "Windows environment does not support fork" if ServerEngine.windows? && impl_class == ServerEngine::MultiProcessServer

      config = {
        workers: 4,
        logger: @logger,
        log_stdout: false,
        log_stderr: false,
        unrecoverable_exit_codes: [3, 4, 5],
        stop_immediately_at_unrecoverable_exit: true
      }

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

describe "log level for exited proccess" do
  include_context 'test server and worker'

  before do
    @log_path = "tmp/multi-process-log-level-test-#{SecureRandom.hex(10)}.log"
  end

  after do
    FileUtils.rm_rf(@log_path)
  end

  it 'stop' do
    skip "Windows environment does not support fork" if ServerEngine.windows?

    config = {
      workers: 1,
      logger: ServerEngine::DaemonLogger.new(@log_path),
      log_stdout: false,
      log_stderr: false,
    }

    s = ServerEngine::MultiProcessServer.new(TestWorker) { config.dup }
    t = Thread.new { s.main }

    begin
      wait_for_fork
      test_state(:worker_run).should == 1
    ensure
      s.stop(true)
      t.join
    end

    log_lines = File.read(@log_path).split("\n")
    expect(log_lines[2]).to match(/^I, \[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d+ #\d+\]  INFO -- : Worker 0 finished with status 0$/)
  end

  it 'non zero exit status' do
    skip "Windows environment does not support fork" if ServerEngine.windows?

    config = {
      workers: 1,
      logger: ServerEngine::DaemonLogger.new(@log_path),
      log_stdout: false,
      log_stderr: false,
      unrecoverable_exit_codes: [5],
    }

    s = ServerEngine::MultiProcessServer.new(TestExitWorker) { config.dup }
    raised_error = nil
    Thread.new do
      begin
        s.main
      rescue SystemExit => e
        raised_error = e
      end
    end.join

    test_state(:worker_stop).to_i.should == 0
    raised_error.status.should == 5
    log_lines = File.read(@log_path).split("\n")
    expect(log_lines[1]).to match(/^E, \[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d+ #\d+\] ERROR -- : Worker 0 exited unexpectedly with status 5$/)
  end

  module TestNormalExitWorker
    include TestExitWorker
    def initialize
      super
      @exit_code = 0
    end
  end

  it 'zero exit status' do
    skip "Windows environment does not support fork" if ServerEngine.windows?

    config = {
      workers: 1,
      logger: ServerEngine::DaemonLogger.new(@log_path),
      log_stdout: false,
      log_stderr: false,
    }

    s = ServerEngine::MultiProcessServer.new(TestNormalExitWorker) { config.dup }
    t = Thread.new { s.main }

    begin
      Timeout.timeout(5) do
        sleep 1 until File.read(@log_path).include?("INFO -- : Worker 0 exited with status 0")
      end
    ensure
      s.stop(true)
      t.join
    end

    log_lines = File.read(@log_path).split("\n")
    expect(log_lines[1]).to match(/^I, \[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d+ #\d+\]  INFO -- : Worker 0 exited with status 0$/)
  end
end
