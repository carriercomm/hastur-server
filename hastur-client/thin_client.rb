#!/usr/bin/env ruby

# this is just a whack at a really thin client script
# totally untested at this point, checking in so others can make fun of me
# if we go this route, main should become 3-4 functions and the whole lot should use the __FILE__ trick to
# make it loadable for testing

require 'ffi-rzmq'
require 'yajl'
require 'multi_json'
require 'trollop'
require 'uuid'
require 'socket'
require_relative "../tools/zmq_utils"

MultiJson.engine = :yajl

opts = Trollop::options do
  opt :router, "Router URI",        :type => String, :required => true, :multi => true
  opt :uuid,   "System UUID",       :type => String, :required => true
  opt :port,   "Local socket port", :type => String, :required => true
end

unless opts[:uuid]
  opts[:uuid] = UUID.new.generate
  STDERR.puts "Generated new UUID: #{opts[:uuid].inspect}"
end
UUID = opts[:uuid]

def exec_plugin(plugin_command, plugin_args=[])
  child_out_r, child_out_w = IO.pipe
  child_err_r, child_err_w = IO.pipe

  child_pid = Kernel.spawn(plugin_command, plugin_args, 
    :out => child_out_w,
    :err => child_err_w,
    :rlimit_cpu => 5,   # 5 seconds of CPU time
    :rlimit_as  => 2**5 # 32MB of memory total
  )

  child_out_w.close
  child_err_w.close

  return child_pid, child_out_w, child_err_w
end

def local_listen(port)
  @udp_socket = UDPSocket.new
  @udp_socket.bind port
  [@udp_socket, nil]
end

def process_udp_message(msg)
  hash = MultiJson.decode(msg) rescue nil
  unless hash
    STDERR.puts "Received invalid JSON packet: #{msg.inspect}"
    return
  end

  hash[:uuid] = UUID

  multi_send(@router_socket, MultiJson.encode(hash))
end

def process_local_socket(sock)
  if sock == @udp_socket
    msg, sender = sock.recvfrom(100000)  # More than max UDP packet size
    process_udp_message(msg)
  end
end

def poll_local_sockets(fdlist)
  fdlist = fdlist.compact  # Remove nils for now

  # this select will wait up to 0.1 seconds, so there's no need for an additional sleep call
  r, = IO.select(fdlist, nil, nil, 0.1)

  # Read TCP or UDP
  r.each do
    process_local_socket r
  end
end

def poll_plugin_pids(plugins)
  # if we really want to be paranoid about blocking, use select to check
  # the readability of the filehandles, but really they're either straight EOF
  # once the process dies, or can be read in one swoop
  plugins.each do |pid, info|
    cpid, status = Process.waitpid2(pid, Process::WNOHANG)
    unless cpid.nil?
      # process is dead, we can read all of its data safely without blocking
      plugin_stdout = info[:stdout].readlines()
      plugin_stderr = info[:stderr].readlines()

      forward_plugin_output(router,
        :pid    => cpid,
        :status => status,
        :stdout => plugin_stdout,
        :stderr => plugin_stderr
      )

      plugins.delete cpid
    end
  end
end

def poll_zmq_router(router)
  # TODO: multipart, not be stupid
  rc = router.recvmsg(msg = '', ZMQ::NonBlocking)
  if rc == 0
    yield msg
  end
end

def main
  ctx = ZMQ::Context.new
  router = ctx.socket(ZMQ::DEALER)
  @router_socket = router  # For using in other methods

  opts[:router].each do |router_uri|
    router.connect(router_uri)
  end

  local_udp, local_tcp = local_listen(opts[:port])

  plugins = {}

  loop do
    poll_local_sockets([local_udp, local_tcp])
    poll_plugin_pids(plugins)
    poll_zmq_router router do |msg|
      # for now, dumbly assume all input is plugin exec requests
      plugin_command, plugin_args = process_msg(msg)
      pid, info = exec_plugin(plugin_command, plugin_args)
      plugins[pid] = info
    end
  end
end

main()
