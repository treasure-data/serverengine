require 'socket'
require 'rr'

describe ServerEngine::SocketManager do
  include_context 'test server and worker'

  let(:server_path) do
    if ServerEngine.windows?
      24223
    else
      'tmp/socket_manager_test.sock'
    end
  end

  let(:test_port) do
    9101
  end

  after(:each) do
    File.unlink(server_path) if server_path.is_a?(String) && File.exist?(server_path)
  end

  if ServerEngine.windows?
    context 'Server.generate_path' do
      context 'with socket path as port number' do
        it 'returns a port in the dynamic port range' do
          path = SocketManager::Server.generate_path
          expect(path).to be_between(49152, 65535)
        end

        it 'returns a port which is not excluded' do
          excluded_port_ranges = [
            49152..49251,
            50000..50059,
          ]
          RR.stub(SocketManager::Server).get_excluded_port_ranges { excluded_port_ranges }
          path = SocketManager::Server.generate_path
          excluded_port_ranges.each do |range|
            expect(path).not_to be_between(range.first, range.last)
          end
        end
      end

      it 'can be changed via environment variable' do
        ENV['SERVERENGINE_SOCKETMANAGER_PORT'] = '54321'
        path = SocketManager::Server.generate_path
        expect(path).to be 54321
        ENV.delete('SERVERENGINE_SOCKETMANAGER_PORT')
      end
    end

    context 'Server.open' do
      it 'returns server with automatically selected socket path as port number' do
        server = SocketManager::Server.open
        expect(server.path).to be_between(49152, 65535)
      end
    end

    context 'Server.share_sockets_with_another_server' do
      it 'not supported' do
        server = SocketManager::Server.open(server_path)
        expect { SocketManager::Server.share_sockets_with_another_server(server_path) }.to raise_error(NotImplementedError)
      ensure
        server.close
      end
    end
  else
    context 'Server.generate_path' do
      it 'returns socket path under /tmp' do
        path = SocketManager::Server.generate_path
        expect(path).to include('/tmp/SERVERENGINE_SOCKETMANAGER_')
      end

      it 'can be changed via environment variable' do
        ENV['SERVERENGINE_SOCKETMANAGER_SOCK_DIR'] = '/tmp/foo'
        path = SocketManager::Server.generate_path
        expect(path).to include('/tmp/foo/SERVERENGINE_SOCKETMANAGER_')
        ENV.delete('SERVERENGINE_SOCKETMANAGER_SOCK_DIR')
      end
    end

    context 'Server.open' do
      it 'returns server with automatically selected socket path under /tmp' do
        server = SocketManager::Server.open
        expect(server.path).to include('/tmp/SERVERENGINE_SOCKETMANAGER_')
      end
    end

    context 'Server.share_sockets_with_another_server' do
      it 'shares listen sockets to another server' do
        server = SocketManager::Server.open(server_path)

        client = SocketManager::Client.new(server_path)
        tcp1 = client.listen_tcp('127.0.0.1', 55551)
        udp1 = client.listen_udp('127.0.0.1', 55561)
        udp2 = client.listen_udp('127.0.0.1', 55562)

        another_server = SocketManager::Server.share_sockets_with_another_server(server_path)

        expect([
          another_server.tcp_sockets.keys,
          another_server.tcp_sockets.values.map(&:addr),
          another_server.udp_sockets.keys,
          another_server.udp_sockets.values.map(&:addr),
        ]).to eq([
          server.tcp_sockets.keys,
          server.tcp_sockets.values.map(&:addr),
          server.udp_sockets.keys,
          server.udp_sockets.values.map(&:addr),
        ])
      ensure
        tcp1&.close
        udp1&.close
        udp2&.close
        server&.close
        another_server&.close
      end

      it 'takes over TCP sockets without downtime' do
        manager_server = SocketManager::Server.open(server_path)
        manager_client = SocketManager::Client.new(server_path)

        has_server_started = false
        # The old server starts listening
        thread_server = Thread.new do
          server = manager_client.listen_tcp('127.0.0.1', test_port)
          has_server_started = true
          while socket = server.accept
            incr_test_state(:count)
            socket.close
          end
        ensure
          server&.close
        end

        sleep 0.1 until has_server_started

        # The client starts sending data
        thread_client = Thread.new do
          100.times do |i|
            socket = TCPSocket.new('127.0.0.1', test_port)
            begin
              socket.write("Hello #{i}\n")
            ensure
              socket.close
            end
            sleep 0.01
          end
        end

        sleep 0.5

        # The new server shares the sockets and starts listening in parallel with the old one
        thread_new_server = Thread.new do
          new_manager_server = SocketManager::Server.share_sockets_with_another_server(server_path)
          server = manager_client.listen_tcp('127.0.0.1', test_port)
          while socket = server.accept
            incr_test_state(:count)
            socket.close
          end
        ensure
          new_manager_server&.close
          server&.close
        end

        # Stop the old server
        sleep 0.1
        thread_server.kill
        thread_server.join

        thread_client.join
        wait_for_stop

        # Confirm that server switching was completed without data loss
        expect(test_state(:count)).to eq(100)
      ensure
        manager_server&.close
        thread_server&.kill
        thread_new_server&.kill
        thread_server&.join
        thread_new_server&.join
      end

      it 'takes over UDP sockets without downtime' do
        manager_server = SocketManager::Server.open(server_path)
        manager_client = SocketManager::Client.new(server_path)

        has_server_started = false
        # The old server starts listening
        thread_server = Thread.new do
          server = manager_client.listen_udp('127.0.0.1', test_port)
          has_server_started = true
          while server.recv(10)
            incr_test_state(:count)
          end
        ensure
          server&.close
        end

        sleep 0.1 until has_server_started

        # The client starts sending data
        thread_client = Thread.new do
          100.times do |i|
            socket = UDPSocket.new
            begin
              socket.send("Hello #{i}\n", 0, "127.0.0.1", test_port)
            ensure
              socket.close
            end
            sleep 0.01
          end
        end

        sleep 0.5

        # The new server shares the sockets and starts listening in parallel with the old one
        thread_new_server = Thread.new do
          new_manager_server = SocketManager::Server.share_sockets_with_another_server(server_path)
          server = manager_client.listen_udp('127.0.0.1', test_port)
          while server.recv(10)
            incr_test_state(:count)
          end
        ensure
          new_manager_server&.close
          server&.close
        end

        # Stop the old server
        sleep 0.1
        thread_server.kill
        thread_server.join

        thread_client.join
        wait_for_stop

        # Confirm that server switching was completed without data loss
        expect(test_state(:count)).to eq(100)
      ensure
        manager_server&.close
        thread_server&.kill
        thread_new_server&.kill
        thread_server&.join
        thread_new_server&.join
      end
    end
  end

  context 'with thread' do
    context 'using ipv4' do
      it 'works' do
        server = SocketManager::Server.open(server_path)

        mutex = Mutex.new
        server_thread_started = false

        thread = Thread.new do
          mutex.lock
          server_thread_started = true

          begin
            client = ServerEngine::SocketManager::Client.new(server_path)

            tcp = client.listen_tcp('127.0.0.1', test_port)
            udp = client.listen_udp('127.0.0.1', test_port)

            incr_test_state(:is_tcp_server) if tcp.is_a?(TCPServer)
            incr_test_state(:is_udp_socket) if udp.is_a?(UDPSocket)

            mutex.unlock

            data, _from = udp.recvfrom(10)
            incr_test_state(:udp_data_sent) if data == "ok"

            s = tcp.accept
            s.write("ok")
            s.close
          rescue => e
            p(here: "rescue in server thread", error: e)
            e.backtrace.each do |bt|
              STDERR.puts bt
            end
            raise
          ensure
            tcp.close
            udp.close
          end
        end

        sleep 0.1 until server_thread_started
        sleep 0.1 while mutex.locked?

        u = UDPSocket.new(Socket::AF_INET)
        u.send "ok", 0, '127.0.0.1', test_port
        u.close

        t = TCPSocket.open('127.0.0.1', test_port)
        t.read.should == "ok"
        t.close

        server.close
        thread.join

        test_state(:is_tcp_server).should == 1
        test_state(:is_udp_socket).should == 1
        test_state(:udp_data_sent).should == 1
      end
    end

    context 'using ipv6' do
      it 'works' do
        server = SocketManager::Server.open(server_path)

        mutex = Mutex.new
        server_thread_started = false

        thread = Thread.new do
          Thread.current.abort_on_exception = true
          mutex.lock
          server_thread_started = true

          begin
            client = ServerEngine::SocketManager::Client.new(server_path)

            tcp = client.listen_tcp('::1', test_port)
            udp = client.listen_udp('::1', test_port)

            incr_test_state(:is_tcp_server) if tcp.is_a?(TCPServer)
            incr_test_state(:is_udp_socket) if udp.is_a?(UDPSocket)

            mutex.unlock

            data, _from = udp.recvfrom(10)
            incr_test_state(:udp_data_sent) if data == "ok"

            s = tcp.accept
            s.write("ok")
            s.close
          rescue => e
            p(here: "rescue in server thread", error: e)
            e.backtrace.each do |bt|
              STDERR.puts bt
            end
            raise
          ensure
            tcp.close
            udp.close
          end
        end

        sleep 0.1 until server_thread_started
        sleep 0.1 while mutex.locked?

        u = UDPSocket.new(Socket::AF_INET6)
        u.send "ok", 0, '::1', test_port
        u.close

        t = TCPSocket.open('::1', test_port)
        t.read.should == "ok"
        t.close

        server.close
        thread.join

        test_state(:is_tcp_server).should == 1
        test_state(:is_udp_socket).should == 1
        test_state(:udp_data_sent).should == 1
      end
    end if (TCPServer.open("::1", 0) rescue nil)

    unless ServerEngine.windows?
      context 'using ipv4/ipv6' do
        it 'can bind ipv4/ipv6 together' do
          server = SocketManager::Server.open(server_path)
          client = ServerEngine::SocketManager::Client.new(server_path)

          tcp_v4 = client.listen_tcp('0.0.0.0', test_port)
          udp_v4 = client.listen_udp('0.0.0.0', test_port)
          tcp_v6 = client.listen_tcp('::', test_port)
          udp_v6 = client.listen_udp('::', test_port)

          tcp_v4.close
          udp_v4.close
          tcp_v6.close
          udp_v6.close
          server.close
        end
      end if (TCPServer.open("::", 0) rescue nil)
    end
  end

  if ServerEngine.windows?
    it 'is windows' do
      SocketManager::Client.is_a?(SocketManagerWin::ClientModule)
      SocketManager::Server.is_a?(SocketManagerWin::ServerModule)
    end
  else
    it 'is unix' do
      SocketManager::Client.is_a?(SocketManagerUnix::ClientModule)
      SocketManager::Server.is_a?(SocketManagerUnix::ServerModule)
    end

    context 'with fork' do
      it 'works' do
        server = SocketManager::Server.open(server_path)

        fork do
          server.close

          begin
            client = server.new_client

            tcp = client.listen_tcp('127.0.0.1', test_port)
            udp = client.listen_udp('127.0.0.1', test_port)

            incr_test_state(:is_tcp_server) if tcp.is_a?(TCPServer)
            incr_test_state(:is_udp_socket) if udp.is_a?(UDPSocket)

            data, _from = udp.recvfrom(10)
            incr_test_state(:udp_data_sent) if data == "ok"

            s = tcp.accept
            s.write("ok")
            s.close
          ensure
            tcp.close
            udp.close
          end
        end

        wait_for_fork

        u = UDPSocket.new
        u.send "ok", 0, '127.0.0.1', test_port
        u.close

        t = TCPSocket.open('127.0.0.1', test_port)
        t.read.should == "ok"
        t.close

        server.close

        test_state(:is_tcp_server).should == 1
        test_state(:is_udp_socket).should == 1
        test_state(:udp_data_sent).should == 1
      end
    end
  end

end
