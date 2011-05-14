require 'helper'

class TestConnectionPool < MiniTest::Unit::TestCase

  class NetworkConnection
    def do_something
      sleep 0.1
      'foo'
    end
  end

  def test_basic_multithreaded_usage
    pool = ConnectionPool.new(:size => 5) { NetworkConnection.new }
    threads = []
    10.times do
      threads << Thread.new do
        pool.with do |net|
          net.do_something
        end
      end
    end
    
    a = Time.now
    threads.each(&:join)
    b = Time.now
    assert((b - a) > 0.2)
  end

  def test_timeout
    pool = ConnectionPool.new(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.2
      end
    end
    sleep 0.1
    assert_raises Timeout::Error do
      pool.do_something
    end
  end

  def test_passthru
    pool = ConnectionPool.new(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    assert_equal 'foo', pool.do_something
  end
end