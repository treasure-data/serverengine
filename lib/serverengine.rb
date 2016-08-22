#
# ServerEngine
#
# Copyright (C) 2012-2013 Sadayuki Furuhashi
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module ServerEngine

  require 'sigdump'

  require 'serverengine/version'

  require 'serverengine/utils' # ServerEngine.windows? and other util methods

  require 'serverengine/daemon'
  require 'serverengine/supervisor'
  require 'serverengine/server'
  require 'serverengine/worker'
  require 'serverengine/socket_manager'

  def self.create(server_module, worker_module, load_config_proc={}, &block)
    Daemon.new(server_module, worker_module, load_config_proc, &block)
  end

  def self.ruby_bin_path
    if ServerEngine.windows?
      require 'windows/library'
      ruby_path = "\0" * 256
      Windows::Library::GetModuleFileName.call(0, ruby_path, 256)
      return ruby_path.rstrip.gsub(/\\/, '/')
    else
      return File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["RUBY_INSTALL_NAME"]) + RbConfig::CONFIG["EXEEXT"]
    end
  end
end
