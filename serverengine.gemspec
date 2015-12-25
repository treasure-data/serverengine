require File.expand_path 'lib/serverengine/version', File.dirname(__FILE__)

Gem::Specification.new do |gem|
  gem.name          = "serverengine"
  gem.version       = ServerEngine::VERSION

  gem.authors       = ["Sadayuki Furuhashi"]
  gem.email         = ["frsyuki@gmail.com"]
  gem.description   = %q{A framework to implement robust multiprocess servers like Unicorn}
  gem.summary       = %q{ServerEngine - multiprocess server framework}
  gem.homepage      = "https://github.com/fluent/serverengine"
  gem.license       = "Apache 2.0"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.has_rdoc = false

  gem.required_ruby_version = ">= 1.9.3"

  gem.add_dependency "sigdump", ["~> 0.2.2"]

  gem.add_development_dependency "rake", [">= 0.9.2"]
  gem.add_development_dependency "rspec", ["~> 2.13.0"]
end
