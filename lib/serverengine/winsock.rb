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

  end

  module WinSockWrapper
    extend Fiddle::Importer

    rubydll_path = Dir.glob(RbConfig.expand("$(bindir)")+"/msvcr*ruby*.dll").first
    dlload rubydll_path

    extern "int rb_w32_wrap_io_handle(int, int)"
  end
end
