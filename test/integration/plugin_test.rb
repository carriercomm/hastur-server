#!/usr/bin/env ruby

require "test/unit"
require_relative "./integration_test_helper"
require 'hastur-server/message'
require 'multi_json'
require 'nodule/topology'
require 'nodule/process'
require 'nodule/unixsocket'
require 'nodule/zeromq'
require 'nodule/console'

class PluginTest < Test::Unit::TestCase
  def setup
    set_test_alarm(30) # helper

    @plugin_text = MultiJson.encode("{\"status\": 0, \"message\": \"OK - plugin success!\"}")
    @plugin_request = <<EOJSON
{
  "plugin_path": "/bin/echo",
  "plugin_args": [#{@plugin_text}],
  "timestamp": #{Time.now.to_f * 1_000_000}
}
EOJSON

    @topology = Nodule::Topology.new(
      :greenio       => Nodule::Console.new(:fg => :green),
      :redio         => Nodule::Console.new(:fg => :red),
      :cyanio        => Nodule::Console.new(:fg => :cyan),
      :client1unix   => Nodule::UnixSocket.new,
      :router        => Nodule::ZeroMQ.new(:uri => :gen),
      :event         => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :heartbeat     => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :capture, :limit => 2),
      :registration  => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain,   :limit => 1),
      :stat          => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :log           => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :error         => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :redio),
      :rawdata       => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :direct        => Nodule::ZeroMQ.new(:connect => ZMQ::PUSH, :uri => :gen),
      :control       => Nodule::ZeroMQ.new(:connect => ZMQ::REQ,  :uri => :gen),
      :routersvc     => Nodule::Process.new(
        HASTUR_ROUTER_BIN,
        '--uuid',          R1UUID,
        '--router',        :router,
        '--event',         :event,
        '--heartbeat',     :heartbeat,
        '--registration',  :registration,
        '--stat',          :stat,
        '--log',           :log,
        '--error',         :error,
        '--direct',        :direct,
        '--rawdata',       :rawdata,
        '--control',       :control,
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio,
      ),
      :client1svc    => Nodule::Process.new(
        HASTUR_CLIENT_BIN,
        '--uuid',         C1UUID,
        '--router',       :router,
        '--unix',         :client1unix,
        '--ack-timeout',  1,
        '--heartbeat',    300,
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio,
      ),
    )

    @topology.start_all
  end

  def teardown
    set_test_alarm(3) # helper
    @topology.stop_all
    cancel_test_alarm
  end

  def test_plugin
    msg = Hastur::Message::PluginExec.new(:to => C1UUID, :from => C2UUID, :payload => @plugin_request)

    @topology.wait :registration, 1

    rc = msg.send @topology[:direct].socket
    assert rc > -1, "zeromq send must return > -1 (errno: #{ZMQ::Util.error_string})"

    @topology.wait :heartbeat, 2

    messages = @topology[:heartbeat].output.pop
    refute_nil messages, "should have caught some zmq messages"
    assert messages.count > 0, "should have caught some zmq messages"
    envelope = Hastur::Envelope.parse messages[-2]
    refute_nil envelope, "should have captured a valid envelope"
    message = Hastur::Message::Heartbeat.new :envelope => envelope, :payload => messages[-1]
    refute_nil message, "should have captured a valid message"

    data = message.decode
    assert_kind_of Hash, data, "message.decode must return a hash"

    assert_kind_of Fixnum, data[:pid], "plugin result 'pid' should be a number"
    assert_kind_of Fixnum, data[:exit], "plugin result 'exit' should be a number"
    assert_equal 0, data[:exit], "plugin result should be 0"

    # TODO: client plugin output isn't parsed - this is a bug that must be fixed first
  end
end
