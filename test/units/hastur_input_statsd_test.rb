#!/usr/bin/env ruby
require_relative "../test_helper"

require 'minitest/autorun'
require 'hastur-server/input/statsd'

class TestHasturInputStatsd < MiniTest::Unit::TestCase
  def test_binary_garbage
    # early testing found random results from random binary data because I missed escaping a pipe
    # running at least 10 times should shake out accidental ascii in random data
    10.times do
      msg = open("/dev/urandom", "rb") do |io|
        io.read(1024)
      end
      stat = Hastur::Input::Statsd.decode(msg)
      assert_nil stat, "should return nil when fed binary garbage"
    end
  end

  def test_json_doesnt_match
    stat = Hastur::Input::Statsd.decode("{\"foo\": \"bar\"}")
    assert_nil stat, "should return nil when fed valid JSON"

    stat = Hastur::Input::Statsd.decode("{\"foo:123:c\": \"bar:321:ms\"}")
    assert_nil stat, "should return nil when fed valid JSON, even if it contains matchable text"

    # the decoder must be extra paranoid to not match JSON by accident - it restricts the name
    # but just make extra sure here
    stat = Hastur::Input::Statsd.decode("{globs:1|c")
    assert_nil stat, "should return nil when fed a matchable STATSD that starts with {"
  end

  def test_statsd_counter_simple
    msg = "globs:1|c"
    stat = Hastur::Input::Statsd.decode(msg)
    refute_nil stat, "should match and return data for '#{msg}'"
    assert_equal "globs", stat[:name],  "name matches input: '#{msg}'"
    assert_equal 1,       stat[:value], "value matches input: '#{msg}'"
    assert_equal "c",     stat[:labels][:units], "unit matches input: '#{msg}'"

    stat = Hastur::Input::Statsd.decode_packet("globs:1|c")
    refute_nil stat, "should match and return data for '#{msg}'"
    assert_equal 2, stat[:value], "value incremented: '#{msg}'"
  end

  def test_statsd_counter_simple2
    msg = "gorts:1|c|@0.1"
    stat = Hastur::Input::Statsd.decode_packet(msg)
    refute_nil stat, "should match and return data for '#{msg}'"
    assert_equal "gorts",  stat[:name],  "name matches input: '#{msg}'"
    assert_equal 1,        stat[:value], "value matches input: '#{msg}'"
    assert_equal "c",      stat[:labels][:units],       "units matches input: '#{msg}'"
    assert_equal "@0.1",   stat[:labels][:sample_rate], "sample rate matches input: '#{msg}'"
  end

  def test_statsd_timer
    msg = "glork:320|ms"
    stat = Hastur::Input::Statsd.decode_packet(msg)
    refute_nil stat, "should match and return data for '#{msg}'"
    assert_equal "glork", stat[:name],  "name matches input: '#{msg}'"
    assert_equal 320,     stat[:value], "value matches input: '#{msg}'"
    assert_equal "ms",    stat[:labels][:units], "unit matches input: '#{msg}'"
  end

  def test_ots_real_data
    msg = "ots.worker.count:375|c"
    stat = Hastur::Input::Statsd.decode_packet(msg)
    refute_nil stat, "should match and return data  '#{msg}'"
    assert_equal "ots.worker.count",   stat[:name], "name matches input: '#{msg}'"
    assert_equal 375,                  stat[:value], "value matches input: '#{msg}'"
    assert_equal "c",                  stat[:labels][:units], "unit matches input: '#{msg}'"
    assert_equal :counter,            stat[:type], "message type matches input: '#{msg}'"
  end
end

