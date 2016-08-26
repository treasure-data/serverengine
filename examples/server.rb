require 'serverengine'

require 'json'
require 'optparse'

# This is a script to run ServerEngine and SocketManager as a real process.
# bundle exec ruby example/server.rb [-t TYPE] [-w NUM]
# available type of workers are: embedded(default), process, thread, spawn

foreground = false
supervisor = false
worker_type = nil
workers = 4
exit_with_code = nil
exit_at_seconds = 5
exit_at_random = false
stop_immediately_at_exit = false
unrecoverable_exit_codes = []

opt = OptionParser.new
opt.on('-f'){ foreground = true }
opt.on('-x'){ supervisor = true }
opt.on('-t TYPE'){|v| worker_type = v }
opt.on('-w NUM'){|v| workers = v.to_i }
opt.on('-e NUM'){|v| exit_with_code = v.to_i }
opt.on('-s NUM'){|v| exit_at_seconds = v.to_i }
opt.on('-r'){ exit_at_random = true }
opt.on('-i'){ stop_immediately_at_exit = true }
opt.on('-u NUM'){|v| unrecoverable_exit_codes << v.to_i }
opt.parse!(ARGV)

if exit_with_code
  ENV['EXIT_WITH_CODE'] = exit_with_code.to_s
  ENV['EXIT_AT_SECONDS'] = exit_at_seconds.to_s
  if exit_at_random
    ENV['EXIT_AT_RANDOM'] = 'true'
  end
end

module MyServer
  attr_reader :socket_manager_path

  def before_run
    @socket_manager_path = ServerEngine::SocketManager::Server.generate_path
    @socket_manager_server = ServerEngine::SocketManager::Server.open(@socket_manager_path)
  rescue Exception => e
    logger.error "unexpected error in server, class #{e.class}: #{e.message}"
    raise
  end

  def after_run
    logger.info "Server stopped."
    @socket_manager_server.close
  end
end

module MyWorker
  def initialize
    @stop = false
    @socket_manager = ServerEngine::SocketManager::Client.new(server.socket_manager_path)
    @exit_with_code = ENV.key?('EXIT_WITH_CODE') ? ENV['EXIT_WITH_CODE'].to_i : nil
    @exit_at_seconds = ENV.key?('EXIT_AT_SECONDS') ? ENV['EXIT_AT_SECONDS'].to_i : nil
    @exit_at_random = ENV.key?('EXIT_AT_RANDOM')
  end

  def main
    # test to listen the same port
    logger.info "Starting to run Worker."
    _listen_sock = @socket_manager.listen_tcp('0.0.0.0', 12345)
    stop_at = if @exit_with_code
                stop_seconds = @exit_at_random ? rand(@exit_at_seconds) : @exit_at_seconds
                logger.info "Stop #{stop_seconds} seconds later with code #{@exit_with_code}."
                Time.now + stop_seconds
              else
                nil
              end
    until @stop
      if stop_at && Time.now >= stop_at
        logger.info "Exitting with code #{@exit_with_code}"
        exit! @exit_with_code
      end
      logger.info "Awesome work!"
      sleep 1
    end
    logger.info "Exitting"
  rescue Exception => e
    logger.warn "unexpected error, class #{e.class}: #{e.message}"
    raise
  end

  def stop
    @stop = true
  end
end

module MySpawnWorker
  def spawn(process_manager)
    env = {
      'SERVER_ENGINE_CONFIG' => config.to_json,
      'SERVER_ENGINE_SOCKET_MANAGER_PATH' => server.socket_manager_path,
    }
    if ENV['EXIT_WITH_CODE']
      env['EXIT_WITH_CODE'] = ENV['EXIT_WITH_CODE']
      env['EXIT_AT_SECONDS'] = ENV['EXIT_AT_SECONDS']
      if ENV['EXIT_AT_RANDOM']
        env['EXIT_AT_RANDOM'] = 'true'
      end
    end
    process_manager.spawn(env, "ruby", File.expand_path("../spawn_worker_script.rb", __FILE__))
  rescue Exception => e
    logger.error "unexpected error, class #{e.class}: #{e.message}"
    raise
  end
end

opts = {
  daemonize: !foreground,
  daemon_process_name: 'mydaemon',
  supervisor: supervisor,
  log: 'myserver.log',
  pid_path: 'myserver.pid',
  worker_type: worker_type,
  workers: workers,
}
if stop_immediately_at_exit
  opts[:stop_immediately_at_unrecoverable_exit] = true
end
unless unrecoverable_exit_codes.empty?
  opts[:unrecoverable_exit_codes] = unrecoverable_exit_codes
end

worker_klass = MyWorker
if worker_type == 'spawn'
  worker_klass = MySpawnWorker
end
se = ServerEngine.create(MyServer, worker_klass, opts)

se.run
