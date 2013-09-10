
describe ServerEngine::SignalThread do
  it 'start and stop' do
    t = SignalThread.new
    t.stop.should == t
    t.join
  end

  it 'call handler' do
    n = 0

    t = SignalThread.new do |st|
      st.trap('CONT') { n += 1 }
    end

    Process.kill('CONT', Process.pid)
    sleep 0.5

    t.stop.join

    n.should == 1
  end

  it 'SIG_IGN' do
    t = SignalThread.new do |st|
      st.trap('QUIT', 'SIG_IGN')
    end

    Process.kill('QUIT', Process.pid)

    t.stop.join
  end

  it 'signal in handler' do
    n = 0

    t = SignalThread.new do |st|
      st.trap('QUIT') do
        if n < 3
          Process.kill('QUIT', Process.pid)
          n += 1
        end
      end
    end

    Process.kill('QUIT', Process.pid)
    sleep 0.5

    n.should == 3
  end

  it 'stop in handler' do
    n = 0

    t = SignalThread.new do |st|
      st.trap('QUIT') { st.stop }
    end

    Process.kill('QUIT', Process.pid)
    sleep 0.5

    t.join
  end

  it 'should not deadlock' do
    n = 0

    t = SignalThread.new do |st|
      st.trap('CONT') { n += 1 }
    end

    (1..10).map {
      Thread.new do
        10.times {
          Process.kill('CONT', Process.pid)
        }
      end
    }.each { |t|
      t.join
    }

    # result won't be 100 because of kernel limitation
    n.should > 0
  end
end

