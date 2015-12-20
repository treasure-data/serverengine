require 'bundler'

begin
  Bundler.setup(:default, :test)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end

require 'serverengine'
include ServerEngine

# require sigdump only in unix, because there is no suport for SIGCONT in windows.
unless ServerEngine.windows?
  require 'sigdump/setup'
end
require 'server_worker_context'

