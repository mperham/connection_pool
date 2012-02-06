Thread.abort_on_exception = true
require 'helper'

class TestConnectionPool < MiniTest::Unit::TestCase

  class NetworkConnection
    def initialize
      @x = 0
    end
    def do_something
      @x += 1
      sleep 0.05
      @x
    end
    def fast
      @x += 1
    end
  end

  def test_basic_multithreaded_usage
    pool = ConnectionPool.new(:size => 5) { NetworkConnection.new }
    threads = []
    15.times do
      threads << Thread.new do
        pool.with_connection do |net|
          net.do_something
        end
      end
    end

    a = Time.now
    result = threads.map(&:value)
    b = Time.now
    assert_operator((b - a), :>, 0.125)
    assert_equal([1,2,3].cycle(5).sort, result.sort)
  end

  def test_timeout
    pool = ConnectionPool.new(:timeout => 0.05, :size => 1) { NetworkConnection.new }
    Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.1
      end
    end
    sleep 0.05
    assert_raises Timeout::Error do
      pool.do_something
    end

    sleep 0.05
    pool.with do |conn|
      refute_nil conn
    end
  end

  def test_passthru
    pool = ConnectionPool.new(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    assert_equal 1, pool.do_something
    assert_equal 2, pool.do_something
  end

  def test_return_value
    pool = ConnectionPool.new(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    result = pool.with_connection do |net|
      net.fast
    end
    assert_equal 1, result
  end

  def test_heavy_threading
    pool = ConnectionPool.new(:timeout => 0.5, :size => 3) { NetworkConnection.new }
    20.times do
      Thread.new do
        pool.with do |net|
          sleep 0.05
        end
      end
    end
    sleep 0.5
  end
end
