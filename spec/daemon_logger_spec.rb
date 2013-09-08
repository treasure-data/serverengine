require_relative 'spec_helper'

describe ServerEngine::DaemonLogger do
  before { FileUtils.mkdir_p("tmp") }
  before { FileUtils.rm_f("tmp/se1.log") }
  before { FileUtils.rm_f("tmp/se2.log") }

  subject { DaemonLogger.new("tmp/se1.log", log_stdout: false, log_stderr: false) }

  it 'reopen' do
    subject.path = 'tmp/se2.log'
    subject.reopen!
    subject.warn "test"

    File.read('tmp/se2.log').should =~ /test$/
  end

  it 'stderr hook 1' do
    subject.hook_stderr!
    STDERR.puts "test"

    File.read('tmp/se1.log').should == "test\n"
  end

  it 'stderr hook 2' do
    log = DaemonLogger.new("tmp/se1.log", log_stdout: false, log_stderr: true)
    STDERR.puts "test"

    File.read('tmp/se1.log').should == "test\n"
  end

  it 'stderr hook and reopen' do
    subject.hook_stderr!
    subject.path = 'tmp/se2.log'
    subject.reopen!
    STDERR.puts "test"

    File.read('tmp/se2.log').should == "test\n"
  end

  it 'default level is debug' do
    subject.debug 'debug'
    File.read('tmp/se1.log').should =~ /debug$/
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
end
