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

module ServerEngine
  module SocketManagerUnix

    module ClientModule
      private

      def connect_peer(path)
        return UNIXSocket.new(path)
      end

      def recv(family, proto, peer, sent)
        server_class = case proto
                       when :tcp then TCPServer
                       when :udp then UDPSocket
                       else
                         raise ArgumentError, "invalid protocol: #{proto}"
                       end
        peer.recv_io(server_class)
      end

      def recv_tcp(family, peer, sent)
        recv(family, :tcp, peer, sent)
      end

      def recv_udp(family, peer, sent)
        recv(family, :udp, peer, sent)
      end
    end

    module ServerModule
      def share_sockets_with_another_server
        another_server = UNIXSocket.new(@path)
        begin
          idx = 0
          while true
            SocketManager.send_peer(another_server, [Process.pid, :share_udp, idx])
            key = SocketManager.recv_peer(another_server)
            break if key.nil?
            @udp_sockets[key] = another_server.recv_io UDPSocket
            idx += 1
          end

          idx = 0
          while true
            SocketManager.send_peer(another_server, [Process.pid, :share_tcp, idx])
            key = SocketManager.recv_peer(another_server)
            break if key.nil?
            @tcp_sockets[key] = another_server.recv_io TCPServer
            idx += 1
          end

          SocketManager.send_peer(another_server, [Process.pid, :share_unix])
          res = SocketManager.recv_peer(another_server)
          raise res if res.is_a?(Exception)
          @server = another_server.recv_io UNIXServer

          start_server(@path)
        ensure
          another_server.close
        end
      end

      private

      def listen_tcp_new(bind_ip, port)
        if ENV['SERVERENGINE_USE_SOCKET_REUSEPORT'] == '1'
          # Based on Addrinfo#listen
          tsock = Socket.new(bind_ip.ipv6? ? ::Socket::AF_INET6 : ::Socket::AF_INET, ::Socket::SOCK_STREAM, 0)
          tsock.ipv6only! if bind_ip.ipv6?
          tsock.setsockopt(:SOCKET, :REUSEPORT, true)
          tsock.setsockopt(:SOCKET, :REUSEADDR, true)
          tsock.bind(Addrinfo.tcp(bind_ip.to_s, port))
          tsock.listen(::Socket::SOMAXCONN)
          tsock.autoclose = false
          TCPServer.for_fd(tsock.fileno)
        else
          # TCPServer.new doesn't set IPV6_V6ONLY flag, so use Addrinfo class instead.
          # TODO: make backlog configurable if necessary
          tsock = Addrinfo.tcp(bind_ip.to_s, port).listen(::Socket::SOMAXCONN)
          tsock.autoclose = false
          TCPServer.for_fd(tsock.fileno)
        end
      end

      def listen_udp_new(bind_ip, port)
        # UDPSocket.new doesn't set IPV6_V6ONLY flag, so use Addrinfo class instead.
        usock = Addrinfo.udp(bind_ip.to_s, port).bind
        usock.autoclose = false
        UDPSocket.for_fd(usock.fileno)
      end

      def start_server(path)
        unless @server
          # return absolute path so that client can connect to this path
          # when client changed working directory
          path = File.expand_path(path)

          begin
            old_umask = File.umask(0077) # Protect unix socket from other users
            @server = UNIXServer.new(path)
          ensure
            File.umask(old_umask)
          end
        end

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
        @tcp_sockets.reject! {|key,lsock| lsock.close; true }
        @udp_sockets.reject! {|key,usock| usock.close; true }
        @server.close unless @server.closed?
        # It cause dead lock and can't finish when joining thread using Ruby 2.1 on linux.
        @thread.join if RUBY_VERSION >= "2.2"
      end

      def send_socket(peer, pid, method, *opts)
        case method
        when :listen_tcp
          bind, port = opts
          sock = listen_tcp(bind, port)
          SocketManager.send_peer(peer, nil)
          peer.send_io sock
        when :listen_udp
          bind, port = opts
          sock = listen_udp(bind, port)
          SocketManager.send_peer(peer, nil)
          peer.send_io sock
        when :share_tcp
          idx, = opts
          key = @tcp_sockets.keys[idx]
          SocketManager.send_peer(peer, key)
          peer.send_io(@tcp_sockets.values[idx]) if key
        when :share_udp
          idx, = opts
          key = @udp_sockets.keys[idx]
          SocketManager.send_peer(peer, key)
          peer.send_io(@udp_sockets.values[idx]) if key
        when :share_unix
          SocketManager.send_peer(peer, nil)
          peer.send_io @server
        else
          raise ArgumentError, "Unknown method: #{method.inspect}"
        end
      end
    end

  end
end
