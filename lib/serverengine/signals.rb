#
# ServerEngine
#
# Copyright (C) 2012-2013 FURUHASHI Sadayuki
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

require 'serverengine/utils'

module ServerEngine
  module Signals
    GRACEFUL_STOP = :TERM
    IMMEDIATE_STOP = :QUIT
    GRACEFUL_RESTART = :USR1
    IMMEDIATE_RESTART = :HUP
    RELOAD = :USR2
    DETACH = :INT
    DUMP = :CONT

    def self.mapping(config, opts={})
      prefix = opts[:prefix]
      {
        graceful_stop: normalized_name(config[:"#{prefix}graceful_stop_signal"] || Signals::GRACEFUL_STOP),
        immediate_stop: normalized_name(config[:"#{prefix}immediate_stop_signal"] || Signals::IMMEDIATE_STOP),
        graceful_restart: normalized_name(config[:"#{prefix}graceful_restart_signal"] || Signals::GRACEFUL_RESTART),
        immediate_restart: normalized_name(config[:"#{prefix}immediate_restart_signal"] || Signals::IMMEDIATE_RESTART),
        reload: normalized_name(config[:"#{prefix}reload_signal"] || Signals::RELOAD),
        detach: normalized_name(config[:"#{prefix}detach_signal"] || Signals::DETACH),
        dump: normalized_name(config[:"#{prefix}dump_signal"] || Signals::DUMP),
      }
    end

    def self.normalized_name(signal)
      sig = signal.to_s.upcase
      if sig[0,3] == "SIG"
        sig = sig[3..-1]
      end
      return sig.to_sym
    end
  end
end
