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
require 'serverengine/daemon_logger'

module ServerEngine

  module ConfigLoader
    def initialize(load_config_proc={}, &block)
      if block
        @load_config_proc = block
      else
        if load_config_proc.is_a?(Hash)
          @load_config_proc = lambda { load_config_proc }
        else
          @load_config_proc = load_config_proc
        end
      end

      @logger = nil

      reload_config
    end

    attr_reader :config
    attr_accessor :logger

    def reload_config
      @config = @load_config_proc.call

      @logger_class = @config[:logger_class] || DaemonLogger

      if @logger
        logdev = logdev_from_config(@config)
        unless logdev.is_a?(IO)
          # Here doesn't allow to change logdev to IO dynamically
          # because Server#start_io_logging_thread can't follow it.
          @logger.logdev = logdev
        end
        @logger.level = @config[:log_level] || 'debug'
      end

      nil
    end

    private

    def create_logger
      if logger = @config[:logger]
        @logger = logger
      else
        @logger = @logger_class.new(logdev_from_config(@config), @config)
      end
    end

    def logdev_from_config(config)
      case c = @config[:log]
      when nil  # default
        return STDERR
      when "-"
        return STDOUT
      else
        return c
      end
    end
  end

end
