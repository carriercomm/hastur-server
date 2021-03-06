require_relative "../test_helper"
require "minitest/autorun"
require "hastur-server/monkeypatch"

class ArrayTest < MiniTest::Unit::TestCase
  def test_fuzzy_filter_1
    list = [ {:a => 'a', :b => 'b'}, {:a => 'a'} ].fuzzy_filter( {:a => 'a'} )
    assert_equal(2, list.size)
  end
  def test_fuzzy_filter_2
    list = [ {:a => 'a', :b => 'b'}, {:a => 'a'} ].fuzzy_filter( {:b => 'b'} )
    assert_equal(1, list.size)
  end
  def test_fuzzy_filter_3
    list = [ {:a => 'a', :b => 'b'}, {:a => 'a'} ].fuzzy_filter( {:b => 'a'} )
    assert_equal(0, list.size)
  end
  def test_fuzzy_filter_4
    list = [ {:a => 'a', :b => 'b'}, {:a => 'a'} ].fuzzy_filter( {:c => 'a'} )
    assert_equal(0, list.size)
  end
  def test_fuzzy_filter_5
    list = [ {:a => 'a', :b => 'b'}, {:a => 'a'} ].fuzzy_filter( {:a => 'a', :b => 'b'} )
    assert_equal(1, list.size)
  end
end
