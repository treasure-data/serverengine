# ServerEngine

ServerEngine is a framework to implement robust multiprocess servers like Unicorn.

## API

### Simplest server

What you need to implement at least is a worker module which implements `run` and `stop` methods.

```ruby
module MyWorker
  def run
    until @stop
      puts "Awesome work!"
      sleep 1
    end
  end

  def stop
    @stop = true
  end
end

se = ServerEngine.create(nil, MyWorker, {
  :daemonize => true,
  :pid_path => 'myserver.pid'
})
se.run
```

Send `TERM` signal to kill the daemon. See also **Signals** section bellow.


### Multiprocess server

Simply set *process* or *thread* to `worker\_type` parameter and number of workers to `workers` parameter.

```ruby
se = ServerEngine.create(nil, MyWorker, {
  :daemonize => true,
  :pid_path => 'myserver.pid',
  :workers => 4,
  :worker_type => 'process',
})
se.run
```

See also **Worker types** section bellow.

#### Multiprocess TCP server

One of typical implementation styles of TCP servers is that a parent process listens socket and child processes accept connections from clients.

You can optionally implement server module to control the parent process.

```ruby
module MyServer
  def before_run
    @sock = TCPServer.new(config[:bind], config[:port])
  end

  attr_reader :sock
end

module MyWorker
  def run
    until @stop
      # you should use Cool.io or EventMachine actually
      c = server.sock.accept
      c.write "Awesome work!"
      c.close
    end
  end

  def stop
    @stop = true
  end
end

se = ServerEngine.create(MyServer, MyWorker, {
  :daemonize => true,
  :pid_path => 'myserver.pid',
  :workers => 4,
  :worker_type => 'process',
  :bind => '0.0.0.0',
  :port => 9071,
})
se.run
```


### Logging

ServerEngine logger rotates logs by 1MB and keeps 5 generations by default.

```ruby
se = ServerEngine.create(MyServer, MyWorker, {
  :log => 'myserver.log',
  :log_level => 'debug',
  :log_rotate_age => 5,
  :log_rotate_size => 1*1024*1024,
})
se.run
```

See also **Configuration** section bellow.


### Enabling supervisor process

Server programs which need to run 24x7 hours need to survive even if a process stalled because of unexpected memory swapping or network errors.

ServerEngine supervisor functionality automatically reboots server process if heartbeat breaks out.

```ruby
se = ServerEngine.create(nil, MyWorker, {
  :daemonize => true,
  :pid_path => 'myserver.pid',
  :supervisor => true,  # enable supervisor process
})
se.run
```

### Live restart

You can restart a server process without waiting for completion of shutdown process (if `supervisor` and `enable\_detach` parameters are enabled).
This feature is useful to minimize downtime where workers take long time to complete tasks.

```
# 1. start server
+------------+   +----------+   +-----------+
| Supervisor |---|  Server  |---| Worker(s) |
+------------+   +----------+   +-----------+

# 2. detach (SIGINT) and waits for completion for several seconds
+------------+    +----------+    +-----------+
| Supervisor |    |  Server  |----| Worker(s) |
+------------+    +----------+    +-----------+

# 3. start new server if the server doesn't exit in a short time
+------------+    +----------+    +-----------+
| Supervisor |\   |  Server  |----| Worker(s) |
+------------+ |  +----------+    +-----------+
               |
               |  +----------+    +-----------+
               \--|  Server  |----| Worker(s) |
                  +----------+    +-----------+

# 4. old server exits
+------------+
| Supervisor |\
+------------+ |
               |
               |  +----------+    +-----------+
               \--|  Server  |----| Worker(s) |
                  +----------+    +-----------+
```

Note that network servers (which listen sockets) shouldn't use live restart because it causes "Address already in use" error. Instead, simply use `worker\_type=process` configuration and send `USR1` to restart only workers. USR1 signal doesn't restart server (by default. See also `restart\_server\_process` parameter). Restarting workers don't wait for completion of all running workers.


### Making dynamic configuration reloading possible

Robust servers should not restart only to update configuration parameters.

```ruby
module MyWorker
  def reload
    @message = config[:message] || "Awesome work!"
    @sleep = config[:sleep] || 1
  end

  def run
    until @stop
      puts @message
      sleep @sleep
    end
  end

  def stop
    @stop = true
  end
end

se = ServerEngine.create(nil, MyWorker) do
  YAML.load_file(config).merge({
    :daemonize => true,
    :worker_type => 'process'
  })
end
se.run
```

Send `USR2` signal to reload configuration file.


## Utilities

### BlockingFlag

`ServerEngine::BlockingFlag` is recommended to stop workers because `stop` methods is called by a different thread from the `run` thread.

```ruby
module MyWorker
  def initialize
    @stop_flag = ServerEngine::BlockingFlag.new
  end

  def run
    until @stop_flag.wait_for_set(1.0)  # or @stop_flag.set?
      puts @message
    end
  end

  def stop
    @stop_flag.set!
  end
end

se = ServerEngine.create(nil, MyWorker) do
  YAML.load_file(config).merge({
    :daemonize => true,
    :worker_type => 'process'
  })
end
se.run
```


### Sigdump

`sigdump` gem installs a signal handler which dumps backtrace of running threads and number of allocated objects per class. It's recommended to call `require sigdump/setup` first.


## Signals

- **TERM:** graceful shutdown
- **QUIT:** immediate shutdown (available only when worker\_type=process)
- **USR1:** graceful restart
- **HUP:** immediate restart (available only when worker\_type=process)
- **USR2:** reload config file and reopen log file
- **INT:** detach process for live restarting (available only when `supervisor` and `enable\_detach` parameters are true. otherwise graceful shutdown)

Immediate shutdown and restart send SIGQUIT signal to worker processes. By default, SIGQUIT kills the process.
Graceful shutdown and restart call `Worker#stop` method and wait for completion of `Worker#run` method.


## Worker types

ServerEngine supports 3 worker types:

- **embedded**: uses a thread to run worker module (default). This type doesn't support immediate shutdown and immediate restart.
- **thread**: uses threads to run worker modules. This type doesn't support immediate shutdown and immediate restart.
- **process**: uses processes to run worker modules. This type doesn't work on Win32 system.


## Configuration

- Daemon
  - **daemonize** enables daemonize (default: false) (not dynamic reloadable)
  - **pid_path** sets the path to pid file (default: don't create pid file) (not dynamic reloadable)
  - **supervisor** enables supervisor if it's true (default: false) (not dynamic reloadable)
  - **daemon\_process\_name** changes process name ($0) of server or supervisor process (not dynamic reloadable)
  - **chuser** changes execution user (not dynamic reloadable)
  - **chgroup** changes execution group (not dynamic reloadable)
  - **chumask** changes umask (not dynamic reloadable)
- Supervisor: available only when `supervisor` parameters is true
  - **server\_process\_name** changes process name ($0) of server process (not dynamic reloadable)
  - **restart\_server\_process** restarts server process when it receives USR1 or HUP signal. (default: false) (not dynamic reloadable)
  - **enable\_detach** enables INT signal (default: true) (not dynamic reloadable)
  - **disable\_reload** disables USR2 signal (default: false) (not dynamic reloadable)
  - **server\restart\_wait** sets wait time before restarting server after last restarting (default: 1.0)
  - **server\_detach\_wait** sets wait time before starting live restart (default: 10.0)
- Multithread server and multiprocess server: available only when `worker\_type` is thread or process
  - **workers** sets number of workers (default: 1)
  - **start\_worker\_delay** sets wait time before starting a new worker (default: 0)
  - **start\_worker\_delay\_rand** randomizes start\_worker\_delay at this ratio (default: 0.2)
- Multiprocess server: available only when `worker\_type` is *process*
  - **worker_heartbeat_interval**
  - **worker_heartbeat_timeout**
  - **worker_graceful_kill_interval**
  - **worker_graceful_kill_interval_increment**
  - **worker_graceful_kill_timeout**
  - **worker_immediate_kill_interval**
  - **worker_immediate_kill_interval_increment
  - **worker_immediate_kill_timeout**
- Logger
  - **log** sets path to log file. Set '-' for STDOUT (default: STDERR)
  - **log\_level** log level: debug, info, warn, error or fatal. (default: debug)
  - **log\_rotate\_age** generations to keep rotated log files (default: 5) (not dynamic reloadable)
  - **log\_rotate\_size** sets the size to rotate log files (default: 1048576) (not dynamic reloadable)
  - **log\_stdout** hooks STDOUT to log file (default: true) (not dynamic reloadable)
  - **log\_stdout** hooks STDERR to log file (default: true) (not dynamic reloadable)
  - **logger\_class** class of the logger instance (default: ServerEngine::DaemonLogger)

