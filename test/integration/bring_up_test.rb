#!/usr/bin/env ruby

require_relative "./integration_test_helper"
require "test/unit"
require 'nodule'
require 'nodule/unixsocket'
require 'nodule/zeromq'
require 'nodule/cassandra'
require 'hastur'
require 'open-uri'

class BringUpTest < Test::Unit::TestCase
  def setup
    set_test_alarm
    sinatra_ready = false
    sinatra_ready_proc = proc do |line|
      sinatra_ready = true if line =~ /== Sinatra.* has taken the stage/
    end
    @sinatra_port = Nodule::Util.random_tcp_port
    @topology = Nodule::Topology.new(
      :greenio      => Nodule::Console.new(:fg => :green),
      :redio        => Nodule::Console.new(:fg => :red),
      :yellowio     => Nodule::Console.new(:fg => :yellow),
      :cyanio       => Nodule::Console.new(:fg => :cyan),
      :router       => Nodule::ZeroMQ.new(:uri => :gen),
      :heartbeat    => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :capture),
      :registration => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :capture),
      :stat         => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :capture),
      :event        => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :log          => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :error        => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :rawdata      => Nodule::ZeroMQ.new(:connect => ZMQ::PULL, :uri => :gen, :reader => :drain),
      :control      => Nodule::ZeroMQ.new(:connect => ZMQ::REP,  :uri => :gen),
      :direct       => Nodule::ZeroMQ.new(:connect => ZMQ::PUSH, :uri => :gen),
      :cassandra    => Nodule::Cassandra.new(:keyspace => "Hastur",
        :stderr => :redio, :verbose => :cyanio, #:stdout => :greenio,
      ),
      :query_server => Nodule::Process.new(HASTUR_QUERY_SERVER_BIN,
        '--cassandra', :cassandra, '--port', @sinatra_port.to_s,
        :stdout => :greenio, :stderr => [sinatra_ready_proc, :greenio], :verbose => :cyanio
      ),
      :client1svc   => Nodule::Process.new(
        HASTUR_CLIENT_BIN, '--uuid', C1UUID, '--heartbeat', 1, '--router', :router,
        :stdout => :greenio, :stderr => :redio, :verbose => :yellowio,
      ),
      :client2svc => Nodule::Process.new(
        HASTUR_CLIENT_BIN, '--uuid', C2UUID, '--heartbeat', 1, '--router', :router, '--port', 8124,
        :stdout => :greenio, :stderr => :redio, :verbose => :yellowio,
      ),
      :router1svc => Nodule::Process.new(
        HASTUR_ROUTER_BIN,
        '--uuid',         R1UUID,
        '--heartbeat',    :heartbeat,
        '--registration', :registration,
        '--event',        :event,
        '--stat',         :stat,
        '--log',          :log,
        '--error',        :error,
        '--rawdata',      :rawdata,
        '--control',      :control,
        '--router',       :router,
        '--direct',       :direct,
        '--hwm',          10,   # Set HWM so this doesn't 'clog'
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio
      ),
      :router2svc => Nodule::Process.new(
        HASTUR_ROUTER_BIN,
        '--uuid',         R2UUID,
        '--heartbeat',    :heartbeat,
        '--registration', :registration,
        '--event',        :event,
        '--stat',         :stat,
        '--log',          :log,
        '--error',        :error,
        '--rawdata',      :rawdata,
        '--control',      :control,
        '--router',       :router,
        '--direct',       :direct,
        '--hwm',          10,   # Set HWM so this doesn't 'clog'
        :stdout => :greenio, :stderr => :redio, :verbose => :cyanio
      ),
      :cass_sink1 => Nodule::Process.new(
        HASTUR_CASS_SINK_BIN,
        '--sinks', :stat, :heartbeat, :registration,
        '--acks-to', :direct,
        '--cassandra', :cassandra,
        :verbose => :cyanio, :stderr => :redio, :stdout => :yellowio
      ),
      :cass_sink2 => Nodule::Process.new(
        HASTUR_CASS_SINK_BIN,
        '--sinks', :stat, :heartbeat, :registration,
        '--acks-to', :direct,
        '--cassandra', :cassandra,
        :verbose => :cyanio, :stderr => :redio, :stdout => :yellowio
      ),
    )

    @topology.start :cassandra
    create_all_column_families(@topology[:cassandra]) # helper

    @topology.start_all_but :client2svc, :router2svc, :cass_sink2
    sleep 0.01 until sinatra_ready
  end

  def teardown
    @topology.stop :cass_sink1, :cass_sink2
    @topology.stop_all
  end

  def test_bring_up
    # Initial testing
    @topology[:heartbeat].require_read_count 2, 5

    messages = @topology[:heartbeat].output
    assert_json_not_empty messages

    # Start up and test second client
    @topology.start :client2svc
    @topology[:registration].require_read_count 2, 5

    # Start up and test second router
    @topology.start :router2svc
    Hastur.counter("My.counter")
    Hastur.udp_port = 8124
    Hastur.counter("My.counter")
    @topology[:stat].require_read_count 2,5

    # Query from 10 minutes ago to 10 minutes from now, just to grab everything
    start_ts = Hastur.timestamp(Time.now.to_i - 600)
    end_ts = Hastur.timestamp(Time.now.to_i + 600)

    url1 = "http://127.0.0.1:#{@sinatra_port}/data/heartbeat/json?uuid=#{C1UUID}&start=#{start_ts}&end=#{end_ts}"
    c1_messages = open(url1).read
    assert_json_not_empty c1_messages

    url2 = "http://127.0.0.1:#{@sinatra_port}/data/heartbeat/values?uuid=#{C2UUID}&start=#{start_ts}&end=#{end_ts}"
    c2_messages = open(url2).read
    assert_json_not_empty c1_messages

    # Start up and test second sink
    @topology.start :cass_sink2
  end
end
