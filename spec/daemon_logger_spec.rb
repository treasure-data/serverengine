
describe ServerEngine::DaemonLogger do
  before { FileUtils.mkdir_p("tmp") }
  before { FileUtils.rm_f("tmp/se1.log") }
  before { FileUtils.rm_f("tmp/se2.log") }
  before { FileUtils.rm_f("tmp/rotate.log") }
  before { FileUtils.rm_f("tmp/rotate.log.0") }
  before { FileUtils.rm_f("tmp/rotate.log.1") }

  subject { DaemonLogger.new("tmp/se1.log", log_stdout: false, log_stderr: false) }

  # Read logfile with removing a log header such as
  # # Logfile created on 2013-09-29 01:14:13 +0900 by logger.rb/36483\n
  def open_logfile(filename)
    File.readlines(filename).tap {|lines| lines.shift if lines.first[0] == '#' }.join
  end

  it 'reopen' do
    subject.path = 'tmp/se2.log'
    subject.reopen!
    subject.warn "test"

    open_logfile('tmp/se2.log').should =~ /test$/
  end

  it 'stderr hook 1' do
    subject.hook_stderr!
    STDERR.puts "test"

    open_logfile('tmp/se1.log').should == "test\n"
  end

  it 'stderr hook 2' do
    log = DaemonLogger.new("tmp/se1.log", log_stdout: false, log_stderr: true)
    STDERR.puts "test"

    open_logfile('tmp/se1.log').should == "test\n"
  end

  it 'stderr hook and reopen' do
    subject.hook_stderr!
    subject.path = 'tmp/se2.log'
    subject.reopen!
    STDERR.puts "test"

    open_logfile('tmp/se2.log').should == "test\n"
  end

  it 'default level is debug' do
    subject.debug 'debug'
    open_logfile('tmp/se1.log').should =~ /debug$/
  end

  it 'level set by int' do
    subject.level = Logger::FATAL
    subject.level.should == Logger::FATAL

    subject.level = Logger::ERROR
    subject.level.should == Logger::ERROR

    subject.level = Logger::WARN
    subject.level.should == Logger::WARN

    subject.level = Logger::INFO
    subject.level.should == Logger::INFO

    subject.level = Logger::DEBUG
    subject.level.should == Logger::DEBUG
  end

  it 'level set by string' do
    subject.level = 'fatal'
    subject.level.should == Logger::FATAL

    subject.level = 'error'
    subject.level.should == Logger::ERROR

    subject.level = 'warn'
    subject.level.should == Logger::WARN

    subject.level = 'info'
    subject.level.should == Logger::INFO

    subject.level = 'debug'
    subject.level.should == Logger::DEBUG
  end

  it 'unknown level' do
    lambda { subject.level = 'unknown' }.should raise_error(ArgumentError)
  end

  it 'stdout logger' do
    STDOUT.should_not_receive(:reopen)
    log = DaemonLogger.new(STDOUT)
    log.debug "stdout logging test"
  end

  it 'log_rotate' do
    # NOTE: log_rotate_age must be >= 3 (it is specification of ::Logger)
    log = DaemonLogger.new("tmp/rotate.log", log_rotate_age: 3, log_rotate_size: 1, log_stdout: false, log_stderr: false)
    log.warn "1st"
    log.warn "2nd"
    log.warn "3rd"

    open_logfile('tmp/rotate.log').should   =~ /3rd$/
    open_logfile('tmp/rotate.log.0').should =~ /2nd$/
    open_logfile('tmp/rotate.log.1').should =~ /1st$/
  end
end
