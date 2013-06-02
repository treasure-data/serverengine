
require 'pstore'

def reset_test_state
  FileUtils.mkdir_p 'tmp'
  FileUtils.rm_f 'tmp/state.pstore'
  FileUtils.touch 'tmp/state.pstore'
end

def incr_test_state(key)
  ps = PStore.new('tmp/state.pstore')
  ps.transaction do
    ps[key] ||= 0
    ps[key] += 1
  end
end

def test_state(key)
  ps = PStore.new('tmp/state.pstore')
  ps.transaction do
    return ps[key] || 0
  end
end

shared_context 'test server and worker' do
  before { reset_test_state }

  def wait_for_fork
    sleep 0.2
  end

  def wait_for_stop
    sleep 0.8
  end

  def wait_for_restart
    sleep 1.5
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
      @stop_flag.wait(5.0)
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

end
