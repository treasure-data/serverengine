require 'timeout'

describe ServerEngine::MultiSpawnServer do
  include_context 'test server and worker'

  describe 'starts worker processes' do
    context 'with command_sender=pipe' do
      it do
        config = {workers: 2, command_sender: 'pipe', log_stdout: false, log_stderr: false}

        s = ServerEngine::MultiSpawnServer.new(TestWorker) { config.dup }
        t = Thread.new { s.main }

        begin
          wait_for_fork

          Timeout.timeout(5) do
            sleep(0.5) until test_state(:worker_run) == 2
          end
          test_state(:worker_run).should == 2
        ensure
          s.stop(true)
          t.join
        end
      end
    end
  end

  describe 'keepalive_workers' do
    let(:config) {
      {
        workers: workers,
        command_sender: 'pipe',
        log_stdout: false,
        log_stderr: false,
        start_worker_delay: start_worker_delay,
        start_worker_delay_rand: 0,
        restart_worker_interval: restart_worker_interval,
      }
    }
    let(:workers) { 3 }
    let(:server) { ServerEngine::MultiSpawnServer.new(TestWorker) { config.dup } }
    let(:monitors) { server.instance_variable_get(:@monitors) }

    context 'default' do
      let(:start_worker_delay) { 0 }
      let(:restart_worker_interval) { 0 }

      it do
        t = Thread.new { server.main }

        begin
          wait_for_fork

          Timeout.timeout(5) do
            sleep(0.5) until test_state(:worker_run) == workers
          end

          monitors.each do |m|
            m.send_stop(true)
          end

          wait_for_restart

          monitors.count { |m| m.alive? }.should == workers
        ensure
          server.stop(true)
          t.join
        end
      end
    end

    context 'with only restart_worker_interval' do
      let(:start_worker_delay) { 0 }
      let(:restart_worker_interval) { 10 }

      it do
        t = Thread.new { server.main }

        begin
          wait_for_fork

          Timeout.timeout(5) do
            sleep(0.5) until test_state(:worker_run) == workers
          end

          monitors.each do |m|
            m.send_stop(true)
          end

          mergin_time = 3

          sleep(restart_worker_interval - mergin_time)
          monitors.count { |m| m.alive? }.should == 0

          sleep(2 * mergin_time)
          monitors.count { |m| m.alive? }.should == workers
        ensure
          server.stop(true)
          t.join
        end
      end
    end

    context 'with only start_worker_delay' do
      let(:start_worker_delay) { 10 }
      let(:restart_worker_interval) { 0 }

      it do
        t = Thread.new { server.main }

        begin
          wait_for_fork

          # This is delayed too, so set longer timeout.
          Timeout.timeout(start_worker_delay * workers) do
            sleep(0.5) until test_state(:worker_run) == workers
          end

          sleep(start_worker_delay)

          monitors.each do |m|
            m.send_stop(true)
          end

          mergin_time = 3

          sleep(start_worker_delay - mergin_time)
          monitors.count { |m| m.alive? }.should satisfy { |c| 0 < c && c < workers }

          sleep(start_worker_delay * (workers - 1))
          monitors.count { |m| m.alive? }.should == workers
        ensure
          server.stop(true)
          t.join
        end
      end
    end

    context 'with both options' do
      let(:start_worker_delay) { 10 }
      let(:restart_worker_interval) { 10 }

      it do
        t = Thread.new { server.main }

        begin
          wait_for_fork

          # This is delayed too, so set longer timeout.
          Timeout.timeout(start_worker_delay * workers) do
            sleep(0.5) until test_state(:worker_run) == workers
          end

          monitors.each do |m|
            m.send_stop(true)
          end

          mergin_time = 3

          sleep(restart_worker_interval - mergin_time)
          monitors.count { |m| m.alive? }.should == 0

          sleep(2 * mergin_time)
          monitors.count { |m| m.alive? }.should satisfy { |c| 0 < c && c < workers }

          sleep(start_worker_delay * (workers - 1))
          monitors.count { |m| m.alive? }.should == workers
        ensure
          server.stop(true)
          t.join
        end
      end
    end
  end
end
