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
require 'fcntl'

module ServerEngine
  module SocketManager

    def self.new_socket_manager
      if $platformwin
        drb_uri = ENV["SERVERENGINE_DRB"]
        begin
          SocketManagerWin::Client.new(drb_uri)
        rescue
          ServerEngine.dump_uncaught_error($!)
        end
      else
        drb_uri = ENV["SERVERENGINE_DRB"]
        tcp_uds_fd = ENV["SERVERENGINE_TCP_UDS"]
        udp_uds_fd = ENV["SERVERENGINE_UDP_UDS"]
        tcp_uds = UNIXSocket.for_fd(tcp_uds_fd.to_i)
        udp_uds = UNIXSocket.for_fd(udp_uds_fd.to_i)
        begin
          SocketManager::Client.new(tcp_uds, udp_uds, drb_uri)
        rescue
          ServerEngine.dump_uncaught_error($!)
        end
      end
    end

    class Client
      def initialize(tcp_uds, udp_uds, drb_uri)
        @tcp_uds = tcp_uds
        @udp_uds = udp_uds
        @sm_server = DRb::DRbObject.new_with_uri(drb_uri)
      end

      def get_udp(bind, port)
        @sm_server.udp_sock_fd(bind, port, @udp_uds.fileno.to_s)
        @udp_uds.recv_io
      end

      def get_tcp(bind, port)
        @sm_server.tcp_sock_fd(bind, port, @tcp_uds.fileno.to_s)
        @tcp_uds.recv_io
      end
    end

    class Server
      def initialize
        @tcp_socks = {}
        @udp_socks = {}
        @unix_sock_server = {}
      end

      def close
        @tcp_socks.each_pair {|key, lsock|
          lsock.close
        }
        @udp_socks.each_pair {|key, usock|
          usock.close
        }
        @unix_sock_server.each_pair {|uds_client, uds_server|
          UNIXSocket.for_fd(uds_client.to_i).close
          uds_server.close
        }
      end

      def new_unix_socket
        unix_sock_server, unix_sock_client = UNIXSocket.pair
        @unix_sock_server[unix_sock_client.fileno.to_s] = unix_sock_server
        unix_sock_client
      end

      def tcp_sock_fd(bind, port, us)

        socks_key = bind.to_s + port.to_s

        if @tcp_socks.has_key?(socks_key)
          @unix_sock_server[us].send_io @tcp_socks[socks_key]
        else
          sock = nil
          begin
            sock = TCPServer.new(bind, port)
            sock.listen(Socket::SOMAXCONN)
          rescue => e
            warn "failed to create TCP socket for #{bind}:#{port}: #{e}"
          end

          @tcp_socks[socks_key] = sock
          @unix_sock_server[us].send_io @tcp_socks[socks_key]
        end
      end

      def udp_sock_fd(bind, port, us)

        socks_key = bind.to_s + port.to_s

        if @udp_socks.has_key?(socks_key)
          @unix_sock_server[us].send_io @udp_socks[socks_key]
        else
          sock = nil
          begin
            if IPAddr.new(IPSocket.getaddress(bind)).ipv4?
              sock = UDPSocket.new
            else
              sock = UDPSocket.new(Socket::AF_INET6)
            end
            sock.bind(bind, port)
          rescue => e
            warn "failed to create UDP socket for #{bind}:#{port}: #{e}"
          end

          @udp_socks[socks_key] = sock

          @unix_sock_server[us].send_io @udp_socks[socks_key]
        end
      end

    end
  end
end
