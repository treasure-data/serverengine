require 'timeout'
require 'timecop'

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
            sleep(0.5) until monitors.count { |m| m && m.alive? } == workers
          end

          monitors.each do |m|
            m.send_stop(true)
          end

          # To prevent the judge before stopping once
          wait_for_stop

          -> {
            Timeout.timeout(5) do
              sleep(0.5) until monitors.count { |m| m.alive? } == workers
            end
          }.should_not raise_error, "Not all workers restarted correctly."
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

          # Wait for initial starting
          Timeout.timeout(5) do
            sleep(0.5) until monitors.count { |m| m && m.alive? } == workers
          end

          monitors.each do |m|
            m.send_stop(true)
          end

          # Wait for all workers to stop and to be set restarting time
          Timeout.timeout(5) do
            sleep(0.5) until monitors.count { |m| m.alive? || m.restart_at.nil? } == 0
          end

          Timecop.freeze

          mergin_time = 3

          Timecop.freeze(Time.now + restart_worker_interval - mergin_time)
          sleep(1.5)
          monitors.count { |m| m.alive? }.should == 0

          Timecop.freeze(Time.now + 2 * mergin_time)
          -> {
            Timeout.timeout(5) do
              sleep(0.5) until monitors.count { |m| m.alive? } == workers
            end
          }.should_not raise_error, "Not all workers restarted correctly."
        ensure
          server.stop(true)
          t.join
        end
      end
    end

    context 'with only start_worker_delay' do
      let(:start_worker_delay) { 3 }
      let(:restart_worker_interval) { 0 }

      it do
        t = Thread.new { server.main }

        begin
          wait_for_fork

          # Initial starts are delayed too, so set longer timeout.
          # (`start_worker_delay` uses `sleep` inside, so Timecop can't skip this wait.)
          Timeout.timeout(start_worker_delay * workers) do
            sleep(0.5) until monitors.count { |m| m && m.alive? } == workers
          end

          # Skip time to avoid getting a delay for the initial starts.
          Timecop.travel(Time.now + start_worker_delay)

          monitors.each do |m|
            m.send_stop(true)
          end

          sleep(3)

          # The first worker should restart immediately.
          monitors.count { |m| m.alive? }.should satisfy { |c| 0 < c && c < workers }

          # `start_worker_delay` uses `sleep` inside, so Timecop can't skip this wait.
          sleep(start_worker_delay * workers)
          monitors.count { |m| m.alive? }.should == workers
        ensure
          server.stop(true)
          t.join
        end
      end
    end

    context 'with both options' do
      let(:start_worker_delay) { 3 }
      let(:restart_worker_interval) { 10 }

      it do
        t = Thread.new { server.main }

        begin
          wait_for_fork

          # Initial starts are delayed too, so set longer timeout.
          # (`start_worker_delay` uses `sleep` inside, so Timecop can't skip this wait.)
          Timeout.timeout(start_worker_delay * workers) do
            sleep(0.5) until monitors.count { |m| m && m.alive? } == workers
          end

          monitors.each do |m|
            m.send_stop(true)
          end

          # Wait for all workers to stop and to be set restarting time
          Timeout.timeout(5) do
            sleep(0.5) until monitors.count { |m| m.alive? || m.restart_at.nil? } == 0
          end

          Timecop.freeze

          mergin_time = 3

          Timecop.freeze(Time.now + restart_worker_interval - mergin_time)
          sleep(1.5)
          monitors.count { |m| m.alive? }.should == 0

          Timecop.travel(Time.now + 2 * mergin_time)
          sleep(1.5)
          monitors.count { |m| m.alive? }.should satisfy { |c| 0 < c && c < workers }

          # `start_worker_delay` uses `sleep` inside, so Timecop can't skip this wait.
          sleep(start_worker_delay * workers)
          monitors.count { |m| m.alive? }.should == workers
        ensure
          server.stop(true)
          t.join
        end
      end
    end
  end
end
