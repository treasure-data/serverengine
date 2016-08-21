require 'serverengine'

require 'json'
require 'optparse'

# This is a script to run ServerEngine and SocketManager as a real process.
# bundle exec ruby example/server.rb [-t TYPE] [-w NUM]
# available type of workers are: embedded(default), process, thread, spawn

worker_type = nil
workers = 4

opt = OptionParser.new
opt.on('-t TYPE'){|v| worker_type = v }
opt.on('-w NUM'){|v| workers = v.to_i }
opt.parse!(ARGV)

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
    @socket_manager_server.close
  end
end

module MyWorker
  def initialize
    @stop = false
    @socket_manager = ServerEngine::SocketManager::Client.new(server.socket_manager_path)
  end

  def main
    # test to listen the same port
    _listen_sock = @socket_manager.listen_tcp('0.0.0.0', 12345)
    until @stop
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
    process_manager.spawn(env, "ruby", File.expand_path("../spawn_worker_script.rb", __FILE__))
  rescue Exception => e
    logger.error "unexpected error, class #{e.class}: #{e.message}"
    raise
  end
end

opts = {
  daemonize: true,
  daemon_process_name: 'mydaemon',
  log: 'myserver.log',
  pid_path: 'myserver.pid',
  worker_type: worker_type,
  workers: workers,
}

worker_klass = MyWorker
if worker_type == 'spawn'
  worker_klass = MySpawnWorker
end
se = ServerEngine.create(MyServer, worker_klass, opts)

se.run
