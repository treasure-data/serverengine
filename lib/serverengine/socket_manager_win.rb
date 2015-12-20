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
  module SocketManagerWin

    require_relative 'winsock'

    module ClientModule
      private

      def connect_peer(addr)
        return TCPSocket.open("127.0.0.1", addr)
      end

      def recv_tcp(peer, sent)
        proto = WinSock::WSAPROTOCOL_INFO.malloc
        proto.to_ptr.ref.ptr[0, WinSock::WSAPROTOCOL_INFO.size] = sent
        sock = WinSock.WSASocketA(Socket::AF_INET, Socket::SOCK_STREAM, 0, proto, 0, 1)
        fd = WinSockWrapper.rb_w32_wrap_io_handle(sock, 0)
        return TCPServer.for_fd(fd)
      end

      def recv_udp(peer, sent)
        proto = WinSock::WSAPROTOCOL_INFO.malloc
        proto.to_ptr.ref.ptr[0, WinSock::WSAPROTOCOL_INFO.size] = sent
        sock = WinSock.WSASocketA(Socket::AF_INET, Socket::SOCK_DGRAM, 0, proto, 0, 1)
        fd = WinSockWrapper.rb_w32_wrap_io_handle(sock, 0)
        return UDPSocket.for_fd(fd)
      end
    end

    module ServerModule
      private

      def listen_tcp_new(bind_ip, port)
        # TODO IPv6 is not supported
        sock = WinSock.WSASocketA(Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP, nil, 0, 1)
        sock_addr = pack_sockaddr(bind_ip, port)
        WinSock.bind(sock, sock_addr, WinSock::SockaddrIn.size)
        WinSock.listen(sock, Socket::SOMAXCONN)

        return sock
      end

      def listen_udp_new(bind_ip, port)
        # TODO IPv6 is not supported
        sock = WinSock.WSASocketA(Socket::AF_INET, Socket::SOCK_DGRAM, Socket::IPPROTO_UDP, nil, 0, 1)
        sock_addr = pack_sockaddr(bind_ip, port)
        WinSock.bind(sock, sock_addr, WinSock::SockaddrIn.size)
        return sock
      end

      def pack_sockaddr(bind_ip, port)
        sock_addr = WinSock::SockaddrIn.malloc
        sock_addr.sin_family = Socket::AF_INET
        sock_addr.sin_port = htons(port)
        sock_addr.sin_addr = WinSock.inet_addr(bind_ip.to_s)
        return sock_addr
      end

      def htons(h)
        [h].pack("S").unpack("n")[0]
      end

      def start_server(addr)
        # TODO: use TCPServer, but this is risky because using not conflict path is easy,
        # but using not conflict port is difficult. Then We had better implement using NamedPipe.
        @server = TCPServer.new("127.0.0.1", addr)
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
        @tcp_sockets.reject! {|key,lhandle|
          lfd=WinSockWrapper.rb_w32_wrap_io_handle(lhandle, 0)
          lsock=TCPServer.for_fd(lfd)
          lsock.close
          true
        }
        @udp_sockets.reject! {|key,uhandle|
          ufd=WinSockWrapper.rb_w32_wrap_io_handle(uhandle, 0)
          usock=UDPSocket.for_fd(ufd)
          usock.close
          true
        }
        @server.close unless @server.closed?
        @thread.join
      end

      def send_socket(peer, pid, method, bind, port)
        case method
        when :listen_tcp
          sock = listen_tcp(bind, port)
          type = Socket::SOCK_STREAM
        when :listen_udp
          sock = listen_udp(bind, port)
          type = Socket::SOCK_DGRAM
        else
          raise ArgumentError, "Unknown method: #{method.inspect}"
        end

        proto = WinSock::WSAPROTOCOL_INFO.malloc
        unless WinSock.WSADuplicateSocketA(sock, pid, proto) == 0
          raise "WSADuplicateSocketA faild (0x%x)" % WinSock.WSAGetLastError
        end
        proto_bin = proto.to_ptr.to_s
        SocketManager.send_peer(peer, proto_bin)
      end
    end
  end
end
