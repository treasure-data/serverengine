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
        uds_drb = ENV["SERVERENGINE_UDS_DRB"]
        unix_socket_client = UNIXSocket.for_fd(uds_drb.split('#').first.to_i)
        drb_uri = uds_drb.split('#').last
        begin
          SocketManager::Client.new(unix_socket_client, drb_uri)
        rescue
          ServerEngine.dump_uncaught_error($!)
        end
      end
    end

    class Client
      def initialize(unix_socket_client, drb_uri)
        @unix_socket_client = unix_socket_client
        @sm_server = DRb::DRbObject.new_with_uri(drb_uri)
      end

      def get_udp(bind, port)
        @sm_server.udp_socket_fd(bind, port)
        @unix_socket_client.recv_io
      end

      def get_tcp(bind, port)
        @sm_server.socket_fd(bind, port)
        @unix_socket_client.recv_io
      end
    end

    class Server
      def initialize
        @tcp_socks = {}
        @udp_socks = {}
        @unix_socket_server = nil
      end

      def close
        @tcp_socks.each_pair {|key, lsock|
          lsock.close
        }
        @udp_socks.each_pair {|key, usock|
          usock.close
        }
        @unix_socket_server.close
        @unix_socket_client.close
      end

      def new_unix_socket
        @unix_socket_server, @unix_socket_client = UNIXSocket.pair
        @unix_socket_client
      end

      def socket_fd(bind, port)
        socks_key = bind.to_s + port.to_s

        if @tcp_socks.has_key?(socks_key)
          @unix_socket_server.send_io @tcp_socks[socks_key]
        else
          sock = nil
          begin
            sock = TCPServer.new(bind, port)
            sock.setsockopt(:SOCKET, :REUSEADDR, true)
            sock.listen(Socket::SOMAXCONN)
          rescue => e
            warn "failed to create TCP socket for #{bind}:#{port}: #{e}"
          end
          sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

          @tcp_socks[socks_key] = sock
          @unix_socket_server.send_io @tcp_socks[socks_key]
        end
      end

      def udp_socket_fd(bind, port)

        socks_key = bind.to_s + port.to_s

        if @udp_socks.has_key?(socks_key)
          @unix_socket_server.send_io @udp_socks[socks_key]
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
          sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

          @udp_socks[socks_key] = sock
          @unix_socket_server.send_io @udp_socks[socks_key]
        end
      end

    end
  end
end
