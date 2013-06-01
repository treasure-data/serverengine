require 'bundler'
require 'sigdump/setup'

begin
  Bundler.setup(:default, :test)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'serverengine'
include ServerEngine

require 'server_worker_context'

