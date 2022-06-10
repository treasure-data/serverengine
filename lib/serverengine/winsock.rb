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
  module WinSock

    require 'fiddle/import'
    require 'fiddle/types'
    require 'socket'
    require 'rbconfig'

    extend Fiddle::Importer

    dlload "ws2_32.dll"
    include Fiddle::Win32Types

    extern "int WSASocketA(int, int, int, void *, int, DWORD)"
    extern "long inet_addr(char *)"
    extern "int bind(int, void *, int)"
    extern "int listen(int, int)"
    extern "int WSADuplicateSocketA(int, DWORD, void *)"
    extern "int WSAGetLastError()"

    SockaddrIn = struct(["short sin_family",
                         "short sin_port",
                         "long sin_addr",
                         "char sin_zero[8]",
                        ])

    WSAPROTOCOL_INFO = struct(["DWORD dwServiceFlags1",
                               "DWORD dwServiceFlags2",
                               "DWORD dwServiceFlags3",
                               "DWORD dwServiceFlags4",
                               "DWORD dwProviderFlags",
                               "DWORD Data1",
                               "WORD  Data2",
                               "WORD  Data3",
                               "BYTE  Data4[8]",
                               "DWORD dwCatalogEntryId",
                               "int ChainLen",
                               "DWORD ChainEntries[7]",
                               "int iVersion",
                               "int iAddressFamily",
                               "int iMaxSockAddr",
                               "int iMinSockAddr",
                               "int iSocketType",
                               "int iProtocol",
                               "int iProtocolMaxOffset",
                               "int iNetworkByteOrder",
                               "int iSecurityScheme",
                               "DWORD dwMessageSize",
                               "DWORD dwProviderReserved",
                               "char szProtocol[256]",
                              ])

    class WSAPROTOCOL_INFO
      def self.from_bin(bin)
        proto = malloc
        proto.to_ptr.ref.ptr[0, size] = bin
        proto
      end

      def to_bin
        to_ptr.to_s
      end
    end

    def self.last_error
      # On Ruby 3.0 calling WSAGetLastError here can't retrieve correct error
      # code because Ruby's internal code resets it.
      # See also:
      # * https://github.com/ruby/fiddle/issues/72
      # * https://bugs.ruby-lang.org/issues/17813
      if Fiddle.respond_to?(:win32_last_socket_error)
        Fiddle.win32_last_socket_error || 0
      else
        self.WSAGetLastError
      end
    end

    INVALID_SOCKET = -1
  end

  module RbWinSock
    extend Fiddle::Importer

    dlload "kernel32"
    extern "int CloseHandle(int)"

    dlload RbConfig::CONFIG['LIBRUBY_SO']
    extern "int rb_w32_map_errno(int)"

    def self.raise_last_error(name)
      errno = rb_w32_map_errno(WinSock.last_error)
      raise SystemCallError.new(name, errno)
    end

    extern "int rb_w32_wrap_io_handle(int, int)"

    def self.wrap_io_handle(sock_class, handle, flags)
      begin
        fd = rb_w32_wrap_io_handle(handle, flags)
        if fd < 0
          raise_last_error("rb_w32_wrap_io_handle(3)")
        end

        sock = sock_class.for_fd(fd)
        wrapped = true
        sock.define_singleton_method(:handle) { handle }

        return sock
      ensure
        unless wrapped
          WinSock.CloseHandle(handle)
        end
      end
    end
  end
end
