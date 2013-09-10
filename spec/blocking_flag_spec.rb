
describe ServerEngine::BlockingFlag do
  subject { BlockingFlag.new }

  it 'set and reset' do
    should_not be_set
    subject.set!
    should be_set
    subject.reset!
    should_not be_set
  end

  it 'set! and reset! return whether it toggled the state' do
    subject.reset!.should == false
    subject.set!.should == true
    subject.set!.should == false
    subject.reset!.should == true
  end

  it 'wait_for_set timeout' do
    start = Time.now

    subject.wait_for_set(0.01)
    elapsed = Time.now - start

    elapsed.should >= 0.01
  end

  it 'wait_for_reset timeout' do
    subject.set!

    start = Time.now

    subject.wait_for_reset(0.01)
    elapsed = Time.now - start

    elapsed.should >= 0.01
  end

  it 'wait' do
    start = Time.now
    elapsed = nil

    started = BlockingFlag.new
    t = Thread.new do
      started.set!
      Thread.pass
      subject.wait_for_set(1)
      elapsed = Time.now - start
    end
    started.wait_for_set

    subject.set!
    t.join

    elapsed.should_not be_nil
    elapsed.should < 0.5
  end
end
