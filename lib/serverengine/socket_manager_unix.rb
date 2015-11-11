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
  module SocketManagerUnix

    module ClientModule
      private

      def connect_peer(path)
        return UNIXSocket.new(path)
      end

      def recv_tcp(peer, sent)
        return peer.recv_io(TCPServer)
      end

      def recv_udp(peer, sent)
        return peer.recv_io(UDPSocket)
      end
    end

    module ServerModule
      private

      def listen_tcp_new(bind_ip, port)
        sock = TCPServer.new(bind_ip.to_s, port)
        sock.listen(Socket::SOMAXCONN)  # TODO make backlog configurable if necessary
        return sock
      end

      def listen_udp_new(bind_ip, port)
        if bind_ip.ipv6?
          sock = UDPSocket.new(Socket::AF_INET6)
        else
          sock = UDPSocket.new
        end
        sock.bind(bind_ip.to_s, port)
        return sock
      end

      def start_server(path)
        # return absolute path so that client can connect to this path
        # when client changed working directory
        path = File.expand_path(path)

        @server = UNIXServer.new(path)

        @thread = Thread.new do
          begin
            while peer = @server.accept
              Thread.new(peer, &method(:process_peer))  # process_peer calls send_socket
            end
          rescue => e
            unless @server.closed?
              ServerEngine.dump_uncaught_error(e)
            end
          end
        end

        return path
      end

      def stop_server
        @server.close unless @server.closed?
        @thread.join
      end

      def send_socket(peer, pid, method, bind, port)
        sock = send(method, bind, port)  # calls listen_tcp or listen_udp

        SocketManager.send_peer(peer, nil)

        peer.send_io sock
      end
    end

  end
end
