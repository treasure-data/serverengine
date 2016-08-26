$LOAD_PATH.unshift File.expand_path("../..", __FILE__)

require 'serverengine'
require 'json'

begin
  conf = JSON.parse(ENV['SERVER_ENGINE_CONFIG'], symbolize_names: true)
  logger = ServerEngine::DaemonLogger.new(conf[:log] || STDOUT, conf)
  logger.info "Starting to run Worker."
  socket_manager = ServerEngine::SocketManager::Client.new(ENV['SERVER_ENGINE_SOCKET_MANAGER_PATH'])
  exit_with_code = ENV.key?('EXIT_WITH_CODE') ? ENV['EXIT_WITH_CODE'].to_i : nil
  exit_at_seconds = ENV.key?('EXIT_AT_SECONDS') ? ENV['EXIT_AT_SECONDS'].to_i : nil
  exit_at_random = ENV.key?('EXIT_AT_RANDOM')
  stop_at = if exit_with_code
              stop_seconds = exit_at_random ? rand(exit_at_seconds) : exit_at_seconds
              logger.info "Stop #{stop_seconds} seconds later with code #{exit_with_code}."
              Time.now + stop_seconds
            else
              nil
            end

  @stop = false
  trap(:SIGTERM) { @stop = true }
  trap(:SIGINT) { @stop = true }

  _listen_sock = socket_manager.listen_tcp('0.0.0.0', 12345)
  until @stop
    if stop_at && Time.now >= stop_at
      logger.info "Exitting with code #{exit_with_code}"
      exit! exit_with_code
    end
    logger.info 'Awesome work!'
    sleep 1
  end
  logger.info 'Exitting'
rescue Exception => e
  logger.error "unexpected error in spawn worker, class #{e.class}: #{e.message}"
end
