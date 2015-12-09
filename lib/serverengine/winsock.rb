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

    require 'ffi'
    extend FFI::Library

    module Constants
      include Socket::Constants

      # Flags
      WSA_FLAG_OVERLAPPED = 0x01
      WSA_FLAG_MULTIPOINT_C_ROOT = 0x02
      WSA_FLAG_MULTIPOINT_C_LEAF = 0x04
      WSA_FLAG_MULTIPOINT_D_ROOT = 0x08
      WSA_FLAG_MULTIPOINT_D_LEAF = 0x10
      WSA_FLAG_ACCESS_SYSTEM_SECURITY = 0x40
      WSA_FLAG_NO_HANDLE_INHERIT = 0x80

      # PROTOCOL
      MAX_PROTOCOL_CHAIN = 7
      WSAPROTOCOL_LENGTH = 256
      GUID_DATA4_LENGTH = 8
    end

    include Constants

    typedef :ulong, :dword
    typedef :uintptr_t, :socket
    typedef :pointer, :ptr
    typedef :ushort, :word
    typedef :uintptr_t, :handle

    ffi_lib :ws2_32

    attach_function :closesocket, [:socket], :int
    attach_function :inet_addr, [:string], :ulong

    attach_function :FreeAddrInfoEx, [:pointer], :void
    attach_function :GetAddrInfo, :getaddrinfo, [:string, :string, :pointer, :pointer], :int
    attach_function :GetAddrInfoW, [:buffer_in, :buffer_in, :pointer, :pointer], :int

    attach_function :GetAddrInfoExA, [:string, :string, :dword, :ptr, :ptr, :ptr, :ptr, :ptr, :ptr, :ptr], :int
    attach_function :GetHostByAddr, :gethostbyaddr, [:string, :int, :int], :pointer
    attach_function :GetHostByName, :gethostbyname, [:string], :pointer
    attach_function :GetProtoByName, :getprotobyname, [:string], :ptr
    attach_function :GetProtoByNumber, :getprotobynumber, [:int], :ptr
    attach_function :GetHostName, :gethostname, [:buffer_out, :int], :int
    attach_function :GetServByName,:getservbyname, [:string, :string], :pointer

    attach_function :WSAAsyncGetHostByAddr, [:uintptr_t, :uint, :string, :int, :int, :buffer_out, :int], :uintptr_t
    attach_function :WSAAsyncGetHostByName, [:uintptr_t, :uint, :string, :buffer_out, :pointer], :uintptr_t
    attach_function :WSAAsyncGetProtoByName, [:uintptr_t, :uint, :string, :buffer_out, :pointer], :uintptr_t
    attach_function :WSAAsyncGetProtoByNumber, [:uintptr_t, :uint, :int, :buffer_out, :pointer], :uintptr_t
    attach_function :WSAAsyncGetServByName, [:uintptr_t, :uint, :int, :string, :buffer_out, :int], :uintptr_t
    attach_function :WSAAsyncGetServByPort, [:uintptr_t, :uint, :int, :string, :buffer_out, :int], :uintptr_t
    attach_function :WSACancelAsyncRequest, [:uintptr_t], :int
    attach_function :WSACleanup, [], :int
    attach_function :WSAConnect, [:socket, :ptr, :int, :ptr, :ptr, :ptr, :ptr], :int
    attach_function :WSAConnectByNameA, [:socket, :string, :string, :ptr, :ptr, :ptr, :ptr, :ptr, :ptr], :bool
    attach_function :WSAEnumNameSpaceProvidersA, [:ptr, :ptr], :int
    attach_function :WSAEnumProtocolsA, [:ptr, :ptr, :ptr], :int
    attach_function :WSAGetLastError, [], :int
    attach_function :WSASocketA, [:int, :int, :int, :ptr, :int, :dword], :socket
    attach_function :WSAStartup, [:word, :ptr], :int
    attach_function :WSADuplicateSocketA, [:socket, :dword, :ptr], :int
    attach_function :bind, [:socket, :ptr, :int], :int
    attach_function :listen, [:socket, :int], :int
    attach_function :WSAAccept, [:socket, :ptr, :int, :int, :int], :socket
    attach_function :accept, [:socket, :ptr, :int], :socket

    rubydll_path = Dir.glob(RbConfig.expand("$(bindir)")+"/msvcr*ruby*.dll").first
    ffi_lib rubydll_path
    attach_function :rb_w32_wrap_io_handle, [:handle, :int], :int

    class InAddr < FFI::Struct
      layout(:s_addr, :ulong)
    end

    class SockaddrIn < FFI::Struct
      layout(
          :sin_family, :short,
          :sin_port, :ushort,
          :sin_addr, InAddr,
          :sin_zero, [:char, 8]
      )
    end

    class GUID < FFI::Struct
      layout(:Data1, :dword, :Data2, :word, :Data3, :word, :Data4, [:uchar, 8])
    end

    class WSAPROTOCOL_CHAIN < FFI::Struct
      layout(:ChainLen, :int, :ChainEntries, [:dword, 7])
    end

    class Sockaddr < FFI::Struct
      layout(:sa_family, :ushort, :sa_data, [:char, 14])
    end

    class WSAPROTOCOL_INFO < FFI::Struct
      layout(
          :dwServiceFlags1, :dword,
          :dwServiceFlags2, :dword,
          :dwServiceFlags3, :dword,
          :dwServiceFlags4, :dword,
          :dwProviderFlags, :dword,
          :ProviderID, GUID,
          :dwCatalogEntryId, :dword,
          :ProtocolChain, WSAPROTOCOL_CHAIN,
          :iVersion, :int,
          :iAddressFamily, :int,
          :iMaxSockAddr, :int,
          :iMinSockAddr, :int,
          :iSocketType, :int,
          :iProtocol, :int,
          :iProtocolMaxOffset, :int,
          :iNetworkByteOrder, :int,
          :iSecurityScheme, :int,
          :dwMessageSize, :dword,
          :dwProviderReserved, :dword,
          :szProtocol, [:char, 256]
      )
    end

    def self.proto_to_map(proto)
      {
          :dwServiceFlags1 => proto[:dwServiceFlags1].to_s,
          :dwServiceFlags2 =>  proto[:dwServiceFlags2].to_s,
          :dwServiceFlags3 =>  proto[:dwServiceFlags3].to_s,
          :dwServiceFlags4 =>  proto[:dwServiceFlags4].to_s,
          :dwProviderFlags =>  proto[:dwProviderFlags].to_s,
          :guid_data1 => proto[:ProviderID][:Data1].to_s,
          :guid_data2 => proto[:ProviderID][:Data2].to_s,
          :guid_data3 => proto[:ProviderID][:Data3].to_s,
          :dwCatalogEntryId =>  proto[:dwCatalogEntryId].to_s,
          :iVersion =>  proto[:iVersion].to_s,
          :iAddressFamily =>  proto[:iAddressFamily].to_s,
          :iMaxSockAddr =>  proto[:iMaxSockAddr].to_s,
          :iMinSockAddr =>  proto[:iMinSockAddr].to_s,
          :iSocketType =>  proto[:iSocketType].to_s,
          :iProtocol =>  proto[:iProtocol].to_s,
          :iProtocolMaxOffset =>  proto[:iProtocolMaxOffset].to_s,
          :iNetworkByteOrder =>  proto[:iNetworkByteOrder].to_s,
          :iSecurityScheme =>  proto[:iSecurityScheme].to_s,
          :dwMessageSize =>  proto[:dwMessageSize].to_s,
          :dwProviderReserved =>  proto[:dwProviderReserved].to_s,
      }
    end

    def self.map_to_proto(proto_map)
      proto = WSAPROTOCOL_INFO.new
      proto[:dwServiceFlags1] =  proto_map[:dwServiceFlags1].to_i
      proto[:dwServiceFlags2] =  proto_map[:dwServiceFlags2].to_i
      proto[:dwServiceFlags3] =  proto_map[:dwServiceFlags3].to_i
      proto[:dwServiceFlags4] =  proto_map[:dwServiceFlags4].to_i
      proto[:dwProviderFlags] =  proto_map[:dwProviderFlags].to_i
      proto[:ProviderID][:Data1] =  proto_map[:guid_data1].to_i
      proto[:ProviderID][:Data2] =  proto_map[:guid_data2].to_i
      proto[:ProviderID][:Data3] =  proto_map[:guid_data3].to_i
      proto[:dwCatalogEntryId] =  proto_map[:dwCatalogEntryId].to_i
      proto[:iVersion] =  proto_map[:iVersion].to_i
      proto[:iAddressFamily] =  proto_map[:iAddressFamily].to_i
      proto[:iMaxSockAddr] =  proto_map[:iMaxSockAddr].to_i
      proto[:iMinSockAddr] =  proto_map[:iMinSockAddr].to_i
      proto[:iSocketType] =  proto_map[:iSocketType].to_i
      proto[:iProtocol] =  proto_map[:iProtocol].to_i
      proto[:iProtocolMaxOffset] =  proto_map[:iProtocolMaxOffset].to_i
      proto[:iNetworkByteOrder] =  proto_map[:iNetworkByteOrder].to_i
      proto[:iSecurityScheme] =  proto_map[:iSecurityScheme].to_i
      proto[:dwMessageSize] =  proto_map[:dwMessageSize].to_i
      proto[:dwProviderReserved] =  proto_map[:dwProviderReserved].to_i
      return proto
    end

  end
end
