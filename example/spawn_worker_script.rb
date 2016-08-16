$LOAD_PATH.unshift File.expand_path("../..", __FILE__)

require 'serverengine'
require 'json'

begin
  conf = JSON.parse(ENV['SERVER_ENGINE_CONFIG'], symbolize_names: true)
  logger = ServerEngine::DaemonLogger.new(conf[:log] || STDOUT, conf)
  socket_manager = ServerEngine::SocketManager::Client.new(ENV['SERVER_ENGINE_SOCKET_MANAGER_PATH'])

  @stop = false
  trap(:SIGTERM) { @stop = true }
  trap(:SIGINT) { @stop = true }

  _listen_sock = socket_manager.listen_tcp('0.0.0.0', 12345)
  until @stop
    logger.info 'Awesome work!'
    sleep 1
  end
  logger.info 'Exitting'
rescue Exception => e
  logger.error "unexpected error in spawn worker, class #{e.class}: #{e.message}"
end
