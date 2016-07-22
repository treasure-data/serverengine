
require 'thread'
require 'yaml'

def reset_test_state
  FileUtils.mkdir_p 'tmp'
  FileUtils.rm_f 'tmp/state.yml'
  FileUtils.touch 'tmp/state.yml'
  $state_file_mutex = Mutex.new
  if ServerEngine.windows?
    open("tmp/daemon.rb", "w") do |f|
      f.puts <<-end
require "serverengine"
require "rspec"
$state_file_mutex = Mutex.new # TODO
require "server_worker_context"
include ServerEngine
Daemon.run_server(TestServer, TestWorker)
      end
    end
  end
end

def windows_daemon_cmdline
  if ServerEngine.windows?
    [ServerEngine.ruby_bin_path, '-I', File.dirname(__FILE__), 'tmp/daemon.rb']
  else
    nil
  end
end

def incr_test_state(key)
  File.open('tmp/state.yml', 'r+') do |f|
    f.flock(File::LOCK_EX)

    $state_file_mutex.synchronize do
      data = YAML.load(f.read) || {} rescue {}
      data[key] ||= 0
      data[key] += 1

      f.pos = 0
      f.write YAML.dump(data)
    end
  end
end

def test_state(key)
  data = YAML.load_file('tmp/state.yml') || {} rescue {}
  return data[key] || 0
end

module TestServer
  def initialize
    incr_test_state :server_initialize
  end

  def before_run
    incr_test_state :server_before_run
  end

  def after_run
    incr_test_state :server_after_run
  end

  def after_start
    incr_test_state :server_after_start
  end

  def stop(stop_graceful)
    incr_test_state :server_stop
    if stop_graceful
      incr_test_state :server_stop_graceful
    else
      incr_test_state :server_stop_immediate
    end
    super
  end

  def restart(stop_graceful)
    incr_test_state :server_restart
    if stop_graceful
      incr_test_state :server_restart_graceful
    else
      incr_test_state :server_restart_immediate
    end
    super
  end

  def reload
    incr_test_state :server_reload
    super
  end

  def detach
    incr_test_state :server_detach
    super
  end
end

module TestWorker
  def initialize
    incr_test_state :worker_initialize
    @stop_flag = BlockingFlag.new
  end

  def before_fork
    incr_test_state :worker_before_fork
  end

  def run
    incr_test_state :worker_run
    5.times do
      # repeats 5 times because signal handlers
      # interrupts wait
      @stop_flag.wait(5.0)
    end
    @stop_flag.reset!
  end

  def stop
    incr_test_state :worker_stop
    @stop_flag.set!
  end

  def reload
    incr_test_state :worker_reload
  end

  def after_start
    incr_test_state :worker_after_start
  end
end

shared_context 'test server and worker' do
  before { reset_test_state }

  def wait_for_fork
    sleep 0.8
  end

  def wait_for_stop
    sleep 0.8
  end

  def wait_for_restart
    sleep 1.5
  end
end
