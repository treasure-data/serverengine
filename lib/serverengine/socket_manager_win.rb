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

require 'socket'
require 'timeout'
require 'ipaddr'
require 'drb/drb'
require 'serverengine/winsock'

module ServerEngine
  module SocketManagerWin
    class Client
      def initialize(drb_uri)
        @drb_uri = drb_uri
      end

      def get_tcp(bind, port)
        sm_server = DRb::DRbObject.new_with_uri(@drb_uri)
        clientd_pid = Process.pid
        proto_map = sm_server.get_tcp_proto(clientd_pid.to_s, bind, port)
        proto = WSAPROTOCOL_INFO.new

        proto[:dwServiceFlags1] =  proto_map[:dwServiceFlags1]
        proto[:dwServiceFlags2] =  proto_map[:dwServiceFlags2]
        proto[:dwServiceFlags3] =  proto_map[:dwServiceFlags3]
        proto[:dwServiceFlags4] =  proto_map[:dwServiceFlags4]
        proto[:dwProviderFlags] =  proto_map[:dwProviderFlags]

        proto[:ProviderID][:Data1] =  proto_map[:guid_data1]
        proto[:ProviderID][:Data2] =  proto_map[:guid_data2]
        proto[:ProviderID][:Data3] =  proto_map[:guid_data3]

        proto[:dwCatalogEntryId] =  proto_map[:dwCatalogEntryId]
        proto[:iVersion] =  proto_map[:iVersion]
        proto[:iAddressFamily] =  proto_map[:iAddressFamily]
        proto[:iMaxSockAddr] =  proto_map[:iMaxSockAddr]
        proto[:iMinSockAddr] =  proto_map[:iMinSockAddr]
        proto[:iSocketType] =  proto_map[:iSocketType]
        proto[:iProtocol] =  proto_map[:iProtocol]
        proto[:iProtocolMaxOffset] =  proto_map[:iProtocolMaxOffset]
        proto[:iNetworkByteOrder] =  proto_map[:iNetworkByteOrder]
        proto[:iSecurityScheme] =  proto_map[:iSecurityScheme]
        proto[:dwMessageSize] =  proto_map[:dwMessageSize]
        proto[:dwProviderReserved] =  proto_map[:dwProviderReserved]

        WSASocketA(AF_INET,SOCK_STREAM,0,proto,0,WSA_FLAG_OVERLAPPED)
      end

      def get_udp(bind, port)
        sm_server = DRb::DRbObject.new_with_uri(@drb_uri)
        clientd_pid = Process.pid
        proto_map = sm_server.get_udp_proto(clientd_pid.to_s, bind, port)
        proto = WSAPROTOCOL_INFO.new

        proto[:dwServiceFlags1] =  proto_map[:dwServiceFlags1]
        proto[:dwServiceFlags2] =  proto_map[:dwServiceFlags2]
        proto[:dwServiceFlags3] =  proto_map[:dwServiceFlags3]
        proto[:dwServiceFlags4] =  proto_map[:dwServiceFlags4]
        proto[:dwProviderFlags] =  proto_map[:dwProviderFlags]

        proto[:ProviderID][:Data1] =  proto_map[:guid_data1]
        proto[:ProviderID][:Data2] =  proto_map[:guid_data2]
        proto[:ProviderID][:Data3] =  proto_map[:guid_data3]

        proto[:dwCatalogEntryId] =  proto_map[:dwCatalogEntryId]
        proto[:iVersion] =  proto_map[:iVersion]
        proto[:iAddressFamily] =  proto_map[:iAddressFamily]
        proto[:iMaxSockAddr] =  proto_map[:iMaxSockAddr]
        proto[:iMinSockAddr] =  proto_map[:iMinSockAddr]
        proto[:iSocketType] =  proto_map[:iSocketType]
        proto[:iProtocol] =  proto_map[:iProtocol]
        proto[:iProtocolMaxOffset] =  proto_map[:iProtocolMaxOffset]
        proto[:iNetworkByteOrder] =  proto_map[:iNetworkByteOrder]
        proto[:iSecurityScheme] =  proto_map[:iSecurityScheme]
        proto[:dwMessageSize] =  proto_map[:dwMessageSize]
        proto[:dwProviderReserved] =  proto_map[:dwProviderReserved]

        WSASocketA(AF_INET,SOCK_DGRAM,0,proto,0,WSA_FLAG_OVERLAPPED)
      end
    end

    class Server
      def initialize
        @tcp_socks = {}
        @udp_socks = {}
      end

      def get_tcp_proto(child_pid, bind, port)
        sock = get_tcp_sock(bind, port)
        proto = WSAPROTOCOL_INFO.new
        WSADuplicateSocketA(sock, child_pid, proto)

        {
          :dwServiceFlags1 => proto[:dwServiceFlags1],
          :dwServiceFlags2 =>  proto[:dwServiceFlags2],
          :dwServiceFlags3 =>  proto[:dwServiceFlags3],
          :dwServiceFlags4 =>  proto[:dwServiceFlags4],
          :dwProviderFlags =>  proto[:dwProviderFlags],

          :guid_data1 => proto[:ProviderID][:Data1],
          :guid_data2 => proto[:ProviderID][:Data2],
          :guid_data3 => proto[:ProviderID][:Data3],

          :dwCatalogEntryId =>  proto[:dwCatalogEntryId],
          :iVersion =>  proto[:iVersion],
          :iAddressFamily =>  proto[:iAddressFamily],
          :iMaxSockAddr =>  proto[:iMaxSockAddr],
          :iMinSockAddr =>  proto[:iMinSockAddr],
          :iSocketType =>  proto[:iSocketType],
          :iProtocol =>  proto[:iProtocol],
          :iProtocolMaxOffset =>  proto[:iProtocolMaxOffset],
          :iNetworkByteOrder =>  proto[:iNetworkByteOrder],
          :iSecurityScheme =>  proto[:iSecurityScheme],
          :dwMessageSize =>  proto[:dwMessageSize],
          :dwProviderReserved =>  proto[:dwProviderReserved]
        }
      end

      def get_udp_proto(child_pid, bind, port)
        sock = get_udp_sock(bind, port)
        proto = WSAPROTOCOL_INFO.new
        WSADuplicateSocketA(sock, child_pid, proto)

        {
          :dwServiceFlags1 => proto[:dwServiceFlags1],
          :dwServiceFlags2 =>  proto[:dwServiceFlags2],
          :dwServiceFlags3 =>  proto[:dwServiceFlags3],
          :dwServiceFlags4 =>  proto[:dwServiceFlags4],
          :dwProviderFlags =>  proto[:dwProviderFlags],

          :guid_data1 => proto[:ProviderID][:Data1],
          :guid_data2 => proto[:ProviderID][:Data2],
          :guid_data3 => proto[:ProviderID][:Data3],

          :dwCatalogEntryId =>  proto[:dwCatalogEntryId],
          :iVersion =>  proto[:iVersion],
          :iAddressFamily =>  proto[:iAddressFamily],
          :iMaxSockAddr =>  proto[:iMaxSockAddr],
          :iMinSockAddr =>  proto[:iMinSockAddr],
          :iSocketType =>  proto[:iSocketType],
          :iProtocol =>  proto[:iProtocol],
          :iProtocolMaxOffset =>  proto[:iProtocolMaxOffset],
          :iNetworkByteOrder =>  proto[:iNetworkByteOrder],
          :iSecurityScheme =>  proto[:iSecurityScheme],
          :dwMessageSize =>  proto[:dwMessageSize],
          :dwProviderReserved =>  proto[:dwProviderReserved]
        }
      end

      def get_tcp_sock(bind, port)

        socks_key = bind.to_s + port.to_s

        if @tcp_socks.has_key?(socks_key)
          @tcp_socks[socks_key]
        else
          socket = WSASocketA(AF_INET,SOCK_STREAM,IPPROTO_TCP,nil,0,WSA_FLAG_OVERLAPPED)
          listen_addr = SockaddrIn.new
          in_addr = InAddr.new
          in_addr[:s_addr] = IPAddr.new(bind).to_i
          listen_addr[:sin_family] = AF_INET
          listen_addr[:sin_port] = htons(port)
          listen_addr[:sin_addr] = in_addr
          WSASocketFunctions::bind(socket, listen_addr, listen_addr.size)
          WSASocketFunctions::listen(socket, Socket::SOMAXCONN)
          @tcp_socks[socks_key] = socket
          @tcp_socks[socks_key]
        end
      end

      def get_udp_sock(bind, port)

        socks_key = bind.to_s + port.to_s

        if @udp_socks.has_key?(socks_key)
          @udp_socks[socks_key]
        else
          socket = WSASocketA(AF_INET,SOCK_DGRAM,IPPROTO_UDP,nil,0,WSA_FLAG_OVERLAPPED)
          sock_addr = SockaddrIn.new
          in_addr = InAddr.new
          in_addr[:s_addr] = IPAddr.new(bind).to_i
          sock_addr[:sin_family] = AF_INET
          sock_addr[:sin_port] = htons(port)
          sock_addr[:sin_addr] = in_addr
          WSASocketFunctions::bind(socket, sock_addr, sock_addr.size)
          @udp_socks[socks_key] = socket
          @udp_socks[socks_key]
        end
      end

      def htons(h)
        [h].pack("S").unpack("n")[0]
      end
    end
  end
end
