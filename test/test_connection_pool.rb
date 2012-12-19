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

    def do_something_with_block
      @x += yield
      sleep 0.05
      @x
    end

    def respond_to?(method_id, *args)
      method_id == :do_magic || super(method_id, *args)
    end
  end

  def test_basic_multithreaded_usage
    pool = ConnectionPool.new(:size => 5) { NetworkConnection.new }
    threads = []
    15.times do
      threads << Thread.new do
        pool.with do |net|
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
      pool.with { |net| net.do_something }
    end

    sleep 0.05
    pool.with do |conn|
      refute_nil conn
    end
  end

  def test_passthru
    pool = ConnectionPool.wrap(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    assert_equal 1, pool.do_something
    assert_equal 2, pool.do_something
    assert_equal 5, pool.do_something_with_block { 3 }
    assert_equal 6, pool.with { |net| net.fast }
  end

  def test_passthru_respond_to
    pool = ConnectionPool.wrap(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    assert pool.respond_to?(:with)
    assert pool.respond_to?(:do_something)
    assert pool.respond_to?(:do_magic)
    refute pool.respond_to?(:do_lots_of_magic)
  end

  def test_return_value
    pool = ConnectionPool.new(:timeout => 0.1, :size => 1) { NetworkConnection.new }
    result = pool.with do |net|
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

  def test_reuses_objects_when_pool_not_saturated
    pool = ConnectionPool.new(:size => 5) { NetworkConnection.new }

    ids = 10.times.map do
      pool.with { |c| c.object_id }
    end

    assert_equal 1, ids.uniq.size
  end

  class Recorder
    def initialize
      @calls = []
    end

    attr_reader :calls

    def do_work(label)
      @calls << label
    end
  end

  def test_nested_checkout
    recorder = Recorder.new
    pool = ConnectionPool.new(:size => 1) { recorder }
    pool.with do |r_outer|
      @other = Thread.new do |t|
        pool.with do |r_other|
          r_other.do_work('other')
        end
      end

      pool.with do |r_inner|
        r_inner.do_work('inner')
      end

      sleep 0.1

      r_outer.do_work('outer')
    end

    @other.join

    assert_equal ['inner', 'outer', 'other'], recorder.calls
  end
end
