require_relative "../test_helper"
require "rack/test"

require "multi_json"
MultiJson.use :json_gem

require "hastur-server/api/v2"
require "hastur-server/api/cass_java_client"

# Timestamp in seconds
NOW_TS = 1330000400000000
PACKED_NOW_TS = [ NOW_TS ].pack("Q>")

# Timestamps in microseconds, rounded down to various sizes.
ROW_5MIN_TS = 1329858600000000
ROW_HOUR_TS = 1329858000000000
ONE_DAY = 24 * 60 * 60 * 1_000_000
ROW_DAY_TS = Hastur::Cassandra.send(:time_segment_for_timestamp, ROW_5MIN_TS, ONE_DAY).to_s

class RetrievalServerTest < Scope::TestCase
  include Rack::Test::Methods

  def app
    @app ||= Hastur::Service::RetrievalV2.new []
  end

  setup do
    @cass_client = mock("Cass client")
    ::Hastur::API::CassandraJavaClient.stubs(:new).with([]).returns(@cass_client)
    @cass_client.stubs(:status_check)

    Hastur.stubs(:timestamp).returns(NOW_TS)
  end

  should "raise no error on /statusz" do
    get "/v2/statusz"
    assert true # Add to count
  end

  context "non-label query" do
    should "do simple lookup for fully-specified query" do
      out_hash = {
        A1UUID => {
          "bobs.gauge" => {
            NOW_TS => 37
          }
        }
      }

      Hastur::Cassandra.expects(:get).with(@cass_client, [A1UUID], ["gauge"],
                                           NOW_TS - 1, NOW_TS, {
        :name => "bobs.gauge",
        :value_only => true,
        :request_ts => NOW_TS}).returns(out_hash)

      result = get "/v2/query?type=gauge&ago=1&uuid=#{A1UUID}&name=bobs.gauge&kind=value"
      hash = MultiJson.load(result.body)
      assert_equal 37, hash[A1UUID]["bobs.gauge"][NOW_TS.to_s]
    end
  end

  # Label queries test a very different chunk of logic with much more
  # complexity.
  context "label query" do

    # This is basically a description of all the interfaces for the three-level index we use
    # for label indices.  It's complicated, yes.  On the other hand, if you find a simple
    # way to do lookup on arbitrary combinations of labels using Cassandra time series,
    # let me know and I'll replace this with it.  DataStax Enterprise or Solandra might
    # kinda-sorta count as "simple" if you squint hard, so we may eventually use one of
    # those, instead.  If you think the tests for them will be simpler, you're not thinking
    # about setup.

    # TODO(noah): Extract data structures from this to top of file

    should "do lookup for fully-specified query" do
      Hastur::Cassandra.expects(:lookup_label_uuids).with(@cass_client, { "foo" => "bar" },
                                                          NOW_TS - 1, NOW_TS).returns({
        "foo" => { "bar" => [ A1UUID ],
                   "barble" => [ A2UUID ] },   # "Bad" value to filter out
      })

      # Note: the wrong UUID supplied below is to test, but should never happen in production.  It
      # would mean that the label UUID index and label stat name index disagreed with each other.
      Hastur::Cassandra.expects(:lookup_label_stat_names).with(@cass_client, [A1UUID],
                                                               { "foo" => "bar", "baz" => "*" },
                                                               NOW_TS - 1,
                                                               NOW_TS).returns({
        "foo" => { "bar" => { "gauge" => { "bobs.gauge" => [A1UUID,A2UUID], # With wrong UUID
                                           "sams.gauge" => [A1UUID] },  # Wrong stat name
                              "counter" => { "bobs.gauge" => [A1UUID] } },  # Wrong type
                   "barble" => { "gauge" => { "bobs.gauge" => [A1UUID] } } },  # Wrong label value
        "baz" => { "zob" => { "gauge" => { "bobs.gauge" => [A1UUID] } } },  # "Must not"
      })
      Hastur::Cassandra.expects(:lookup_label_timestamps).with(@cass_client, {
        "foo" => { "bar" => { "gauge" => { "bobs.gauge" => [A1UUID] } } },
        "baz" => { "zob" => { "gauge" => { "bobs.gauge" => [A1UUID] } } },  # "Must not"
      }, ["baz"], NOW_TS - 1, NOW_TS).returns({
        "gauge" => {
          "#{A1UUID}-#{ROW_HOUR_TS}" => [ "bobs.gauge-#{PACKED_NOW_TS}" ],
        }
      })

      Hastur::Cassandra.expects(:query_cassandra_by_type_rows_cols).with(@cass_client, "gauge", "value",
                                    { "#{A1UUID}-#{ROW_HOUR_TS}" => [ "bobs.gauge-#{PACKED_NOW_TS}" ] },
                                    { :request_ts => NOW_TS, :value_only => true }).returns(
                                      [ ["#{A1UUID}-#{ROW_HOUR_TS}", "bobs.gauge-#{PACKED_NOW_TS}", 37] ])

      final_output = { A1UUID => { "bobs.gauge" => { NOW_TS => 37 } } }
      Hastur::Cassandra.expects(:convert_list_to_hastur_series).with(
        [ ["#{A1UUID}-#{ROW_HOUR_TS}", "bobs.gauge-#{PACKED_NOW_TS}", 37] ], {},
        NOW_TS - 1, NOW_TS,
        { :request_ts => NOW_TS, :value_only => true }).returns(final_output)

      result = get "/v2/query?type=gauge&ago=1&uuid=#{A1UUID}&name=bobs.gauge&kind=value&label=foo:bar,!baz"
      assert_equal MultiJson.dump(final_output, :pretty => true), result.body.strip
    end
  end
end
