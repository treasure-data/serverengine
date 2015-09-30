#
# Fluentd
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
        proto_pack = sm_server.get_tcp_proto(clientd_pid.to_s, bind, port)
        proto_map = MessagePack.unpack(proto_pack)
        proto = WSAPROTOCOL_INFO.new

        proto[:dwServiceFlags1] =  proto_map["dwServiceFlags1"].to_i
        proto[:dwServiceFlags2] =  proto_map["dwServiceFlags2"].to_i
        proto[:dwServiceFlags3] =  proto_map["dwServiceFlags3"].to_i
        proto[:dwServiceFlags4] =  proto_map["dwServiceFlags4"].to_i
        proto[:dwProviderFlags] =  proto_map["dwProviderFlags"].to_i

        proto[:ProviderID][:Data1] =  proto_map["guid_data1"].to_i
        proto[:ProviderID][:Data2] =  proto_map["guid_data2"].to_i
        proto[:ProviderID][:Data3] =  proto_map["guid_data3"].to_i

        proto[:dwCatalogEntryId] =  proto_map["dwCatalogEntryId"].to_i
        proto[:iVersion] =  proto_map["iVersion"].to_i
        proto[:iAddressFamily] =  proto_map["iAddressFamily"].to_i
        proto[:iMaxSockAddr] =  proto_map["iMaxSockAddr"].to_i
        proto[:iMinSockAddr] =  proto_map["iMinSockAddr"].to_i
        proto[:iSocketType] =  proto_map["iSocketType"].to_i
        proto[:iProtocol] =  proto_map["iProtocol"].to_i
        proto[:iProtocolMaxOffset] =  proto_map["iProtocolMaxOffset"].to_i
        proto[:iNetworkByteOrder] =  proto_map["iNetworkByteOrder"].to_i
        proto[:iSecurityScheme] =  proto_map["iSecurityScheme"].to_i
        proto[:dwMessageSize] =  proto_map["dwMessageSize"].to_i
        proto[:dwProviderReserved] =  proto_map["dwProviderReserved"].to_i

        WSASocketA(AF_INET,SOCK_STREAM,0,proto,0,WSA_FLAG_OVERLAPPED)
      end
    end

    class Server
      def initialize
        @socks = {}
      end

      def get_tcp_proto(child_pid, bind, port)
        sock = get_sock(bind, port)
        proto = WSAPROTOCOL_INFO.new
        WSADuplicateSocketA(sock, child_pid, proto)

        # guid_data4 = []
        # for e in 0..7
        #   guid_data4.push proto[:ProviderID][:Data4][e]
        # end

        proto_map = {
            :dwServiceFlags1 => proto[:dwServiceFlags1].to_s,
            :dwServiceFlags2 =>  proto[:dwServiceFlags2].to_s,
            :dwServiceFlags3 =>  proto[:dwServiceFlags3].to_s,
            :dwServiceFlags4 =>  proto[:dwServiceFlags4].to_s,
            :dwProviderFlags =>  proto[:dwProviderFlags].to_s,

            :guid_data1 => proto[:ProviderID][:Data1].to_s,
            :guid_data2 => proto[:ProviderID][:Data2].to_s,
            :guid_data3 => proto[:ProviderID][:Data3].to_s,
            # :guid_data4 => guid_data4,

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
            :dwProviderReserved =>  proto[:dwProviderReserved].to_s
        }

        MessagePack.pack(proto_map)
      end

      def get_sock(bind, port)

        socks_key = bind.to_s + port.to_s

        if @socks.has_key?(socks_key)
          @socks[socks_key]
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
          @socks[socks_key] = socket
          @socks[socks_key]
        end
      end

      def htons(h)
        [h].pack("S").unpack("n")[0]
      end
    end
  end
end
