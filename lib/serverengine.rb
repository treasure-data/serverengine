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

  here = File.expand_path(File.dirname(__FILE__))

  {
    :BlockingFlag => 'serverengine/blocking_flag',
    :SignalThread => 'serverengine/signal_thread',
    :DaemonLogger => 'serverengine/daemon_logger',
    :ConfigLoader => 'serverengine/config_loader',
    :Daemon => 'serverengine/daemon',
    :Supervisor => 'serverengine/supervisor',
    :Server => 'serverengine/server',
    :EmbeddedServer => 'serverengine/embedded_server',
    :MultiWorkerServer => 'serverengine/multi_worker_server',
    :MultiProcessServer => 'serverengine/multi_process_server',
    :MultiThreadServer => 'serverengine/multi_thread_server',
    :MultiSpawnServer => 'serverengine/multi_spawn_server',
    :ProcessManager => 'serverengine/process_manager',
    :Worker => 'serverengine/worker',
    :VERSION => 'serverengine/version',
  }.each_pair {|k,v|
    autoload k, File.expand_path(v, File.dirname(__FILE__))
  }

  [
    'serverengine/utils',
  ].each {|v|
    require File.join(here, v)
  }

  def self.create(server_module, worker_module, load_config_proc={}, &block)
    Daemon.new(server_module, worker_module, load_config_proc, &block)
  end
end
