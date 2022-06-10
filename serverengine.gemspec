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

  gem.required_ruby_version = ">= 2.1.0"

  gem.add_dependency "sigdump", ["~> 0.2.2"]

  # rake v12.x doesn't work with rspec 2. rspec should be updated to 3
  gem.add_development_dependency "rake", ["~> 11.0"]
  gem.add_development_dependency "rspec", ["~> 2.13.0"]

  gem.add_development_dependency 'rake-compiler-dock', ['~> 0.5.0']
  gem.add_development_dependency 'rake-compiler', ['~> 0.9.4']

  gem.add_development_dependency "timecop", ["~> 0.9.5"]
end
