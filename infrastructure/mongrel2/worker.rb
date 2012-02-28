require 'ffi-rzmq'
require 'multi_json'

handler_thread = Thread.new do
  handler_ctx = ZMQ::Context.new(1)

  receive_queue = handler_ctx.socket(ZMQ::PULL)
  receive_queue.connect("tcp://127.0.0.1:9999")

  response_publisher = handler_ctx.socket(ZMQ::PUB)
  response_publisher.connect("tcp://127.0.0.1:9998")
  response_publisher.setsockopt(ZMQ::IDENTITY, "82209006-86FF-4982-B5EA-D1E29E55D481")

  stop_queue = handler_ctx.socket(ZMQ::PULL)
  stop_queue.connect("ipc://shutdown_queue")

  stopped = false
  until stopped do
    selected_queue = ZMQ.select([receive_queue, stop_queue])
    if selected_queue[0][0] == stop_queue # Anything on the stop_queue ends processing
      stop_queue.close
      receive_queue.close
      response_publisher.close
      handler_ctx.close
      stopped = true
    else
      # Request comes in as "UUID ID PATH SIZE:HEADERS,SIZE:BODY,"
      sender_uuid, client_id, request_path, request_message = receive_queue.recv(0).split(' ', 4)
      len, rest = request_message.split(':', 2)
      headers = MultiJson.decode(rest[0...len.to_i])
      len, rest = rest[(len.to_i+1)..-1].split(':', 2)
      body = rest[0...len.to_i]

      if headers['METHOD'] == 'JSON' and MultiJson.decode(body)['type'] == 'disconnect'
        next # A client has disconnected, might want to do something here...
      end

      # Response goes out as "UUID SIZE:ID ID ID, BODY"
      content_body = "Hello world!"
      response_value = "#{sender_uuid} 1:#{client_id}, HTTP/1.1 200 OK\r\nContent-Length: #{content_body.size}\r\n\r\n#{content_body}"
      response_publisher.send(response_value, 0)
    end
  end
end

ctx = ZMQ::Context.new(1)
stop_push_queue = ctx.socket(ZMQ::PUSH)
trap('INT') do # Send a message to shutdown on SIGINT
  stop_push_queue.bind("ipc://shutdown_queue")
  stop_push_queue.send("shutdown")
end

handler_thread.join

stop_push_queue.close