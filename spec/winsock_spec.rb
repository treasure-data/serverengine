describe ServerEngine::WinSock do
  # On Ruby 3.0, you need to use fiddle 1.0.8 or later to retrieve a correct
  # error code. In addition, you need to specify the path of fiddle by RUBYLIB
  # or `ruby -I` when you use RubyInstaller because it loads Ruby's bundled
  # fiddle before initializing gem.
  # See also:
  # * https://github.com/ruby/fiddle/issues/72
  # * https://bugs.ruby-lang.org/issues/17813
  # * https://github.com/oneclick/rubyinstaller2/blob/8225034c22152d8195bc0aabc42a956c79d6c712/lib/ruby_installer/build/dll_directory.rb
  context 'last_error' do
    it 'bind error' do
      expect(WinSock.bind(0, nil, 0)).to be -1
      WSAENOTSOCK = 10038
      expect(WinSock.last_error).to be WSAENOTSOCK
    end
  end
end if ServerEngine.windows?
