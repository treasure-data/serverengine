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
require 'etc'

module ServerEngine
  module Privilege
    def self.get_etc_passwd(user)
      if user.to_i.to_s == user
        Etc.getpwuid(user.to_i)
      else
        Etc.getpwnam(user)
      end
    end

    def self.get_etc_group(group)
      if group.to_i.to_s == group
        Etc.getgrgid(group.to_i)
      else
        Etc.getgrnam(group)
      end
    end

    def self.change(user, group)
      if group
        etc_group = get_etc_group(group)
        Process::GID.change_privilege(etc_group.gid)
      end

      if user
        etc_pw = get_etc_passwd(user)
        user_groups = [etc_pw.gid]
        Etc.setgrent
        Etc.group { |gr| user_groups << gr.gid if gr.mem.include?(etc_pw.name) } # emulate 'id -G'

        Process.groups = Process.groups | user_groups
        Process::UID.change_privilege(etc_pw.uid)
      end

      nil
    end
  end
end
