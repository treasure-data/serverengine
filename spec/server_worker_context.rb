
require 'thread'
require 'yaml'

def reset_test_state
  FileUtils.mkdir_p 'tmp'
  FileUtils.rm_f 'tmp/state.yml'
  FileUtils.touch 'tmp/state.yml'
  $state_file_mutex = Mutex.new
  if ServerEngine.windows?
    open("tmp/daemon.rb", "w") do |f|
      f.puts <<-'end_of_script'
require "serverengine"
require "rspec"
$state_file_mutex = Mutex.new # TODO
require "server_worker_context"
include ServerEngine
command_pipe = STDIN.dup
STDIN.reopen(File::NULL)
Daemon.run_server(TestServer, TestWorker, command_pipe: command_pipe)
      end_of_script
    end

    open("tmp/supervisor.rb", "w") do |f|
      f.puts <<-'end_of_script'
require "serverengine"
require "rspec"
$state_file_mutex = Mutex.new # TODO
require "server_worker_context"
include ServerEngine
server = TestServer
worker = TestWorker
config = {command_pipe: STDIN.dup}
STDIN.reopen(File::NULL)
ARGV.each do |arg|
  case arg
  when /^server=(.*)$/
    server = Object.const_get($1)
  when /^worker=(.*)$/
    worker = Object.const_get($1)
  when /^(.*)=(\d+)$/
    config[$1.to_sym] = $2.to_i
  when /^(.*)=(.*)$/
    config[$1.to_sym] = $2
  else
    raise "Unknown parameter: [#{arg}]"
  end
end
sv = Supervisor.new(server, worker, config)
s = sv.create_server(nil)
s.install_signal_handlers
t = Thread.new{ s.main }
s.after_start
t.join
      end_of_script
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

def windows_supervisor_cmdline(server = nil, worker = nil, config = {})
  if ServerEngine.windows?
    cmd = [ServerEngine.ruby_bin_path, '-I', File.dirname(__FILE__), 'tmp/supervisor.rb']
    cmd << "server=#{server}" if server
    cmd << "worker=#{worker}" if worker
    config.each_pair do |k, v|
      cmd << "#{k}=#{v}"
    end
    cmd
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
      data[key]
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

  def dump
    incr_test_state :server_dump
    super
  end
end

module TestWorker
  def initialize
    incr_test_state :worker_initialize
    @stop_flag = ServerEngine::BlockingFlag.new
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

  def spawn(pm)
    script = <<-EOF
    class WorkerClass
      include TestWorker
      def run
        Thread.new do
          command_pipe = STDIN.dup
          STDIN.reopen(File::NULL)
          Thread.new do
            until @stop_flag.set?
              cmd = command_pipe.gets.chomp
              case cmd
              when "GRACEFUL_STOP", "IMMEDIATE_STOP"
                stop
              when "RELOAD"
                reload
              end
            end
          end
        end
        super
      end
    end
    $state_file_mutex = Mutex.new
    WorkerClass.new.run
    EOF
    cmdline = [ServerEngine.ruby_bin_path] + %w[-rbundler/setup -rrspec -I. -Ispec -rserverengine -r] + [__FILE__] + %w[-e] + [script]
    pm.spawn(*cmdline)
  end
end

module RunErrorWorker
  def run
    incr_test_state :worker_run
    raise StandardError, "error test"
  end
end

module TestExitWorker
  def initialize
    @stop_flag = BlockingFlag.new
    @worker_num = incr_test_state :worker_initialize
    @exit_code = case @worker_num
                 when 1 then 5
                 when 4 then 3
                 else 4
                 end
  end

  def run
    incr_test_state :worker_run
    exit_at = Time.now + @worker_num * 2
    until @stop_flag.wait(0.1)
      exit!(@exit_code) if Time.now >= exit_at
    end
    incr_test_state :worker_finished
  end

  def stop
    incr_test_state :worker_stop
    @stop_flag.set!
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
