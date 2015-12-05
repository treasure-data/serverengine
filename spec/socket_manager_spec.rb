
describe ServerEngine::SocketManager do
  include_context 'test server and worker'

  let(:server_path) do
    'tmp/socket_manager_test.sock'
  end

  let(:server_port) do
    24223
  end

  let(:test_port) do
    9101
  end

  after(:each) do
    File.unlink(server_path) if File.exists?(server_path)
  end

  if ServerEngine.windows?
    it 'is windows' do
      SocketManager::Client.is_a?(SocketManagerWin::ClientModule)
      SocketManager::Server.is_a?(SocketManagerWin::ServerModule)
    end

    context 'with thread' do
      it 'works' do
        server = SocketManager::Server.open(server_port)

        thread = Thread.new{

          client = ServerEngine::SocketManager::Client.new(server_port)
          tcp = client.listen_tcp('127.0.0.1', test_port)
          udp = client.listen_udp('127.0.0.1', test_port)

          incr_test_state(:is_tcp_server) if tcp.is_a?(TCPServer)
          incr_test_state(:is_udp_socket) if udp.is_a?(UDPSocket)

          data, from = udp.recvfrom(10)
          incr_test_state(:udp_data_sent) if data == "ok"

          s = tcp.accept
          s.write("ok")
          s.close
        }

        sleep 1

        u = UDPSocket.new
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

          client = server.new_client

          tcp = client.listen_tcp('127.0.0.1', test_port)
          udp = client.listen_udp('127.0.0.1', test_port)

          incr_test_state(:is_tcp_server) if tcp.is_a?(TCPServer)
          incr_test_state(:is_udp_socket) if udp.is_a?(UDPSocket)

          data, from = udp.recvfrom(10)
          incr_test_state(:udp_data_sent) if data == "ok"

          s = tcp.accept
          s.write("ok")
          s.close
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
