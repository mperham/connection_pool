require_relative 'helper'

class TestConnectionPool < Minitest::Test

  class NetworkConnection
    attr_reader :host

    def initialize(host = nil)
      @host = host
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

  class Recorder
    def initialize
      @calls = []
    end

    attr_reader :calls

    def do_work(label)
      @calls << label
    end
  end

  def use_pool(pool, size)
    Array.new(size) do
      Thread.new do
        pool.with do sleep end
      end
    end.each do |thread|
      Thread.pass until thread.status == 'sleep'
    end.map do |thread|
      thread.kill
      Thread.pass while thread.alive?
    end
  end

  def test_basic_multithreaded_usage
    pool = ConnectionPool.new(:size => 5) { NetworkConnection.new }

    threads = Array.new(15) do
      Thread.new do
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
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { NetworkConnection.new }
    thread = Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    end

    Thread.pass while thread.status == 'run'

    assert_raises Timeout::Error do
      pool.with { |net| net.do_something }
    end

    thread.join

    pool.with do |conn|
      refute_nil conn
    end
  end

  def test_with
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { Object.new }

    pool.with do
      assert_raises Timeout::Error do
        Thread.new { pool.checkout }.join
      end
    end

    assert Thread.new { pool.checkout }.join
  end

  def test_with_connection_args
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { Object.new }

    pool.with 'a.example' do
      assert_raises Timeout::Error do
        Thread.new { pool.checkout }.join
      end
    end

    assert Thread.new { pool.checkout }.join
  end

  def test_with_timeout_override
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { NetworkConnection.new }

    t = Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    end

    Thread.pass while t.status == 'run'

    assert_raises Timeout::Error do
      pool.with { |net| net.do_something }
    end

    pool.with(:timeout => 0.1) do |conn|
      refute_nil conn
    end
  end

  def test_checkin
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { NetworkConnection.new }
    conn = pool.checkout

    t1 = Thread.new do
      pool.checkout
    end

    assert_raises Timeout::Error do
      t1.join
    end

    pool.checkin

    t2 = Thread.new do
      pool.checkout
    end

    assert_same conn, t2.value
  end

  def test_checkin_never_checkout
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { Object.new }

    e = assert_raises ConnectionPool::Error do
      pool.checkin
    end

    assert_equal 'no connections are checked out', e.message
  end

  def test_checkin_no_current_checkout
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { Object.new }

    pool.checkout
    pool.checkin

    assert_raises ConnectionPool::Error do
      pool.checkin
    end
  end

  def test_checkin_twice
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { Object.new }

    pool.checkout
    pool.checkout

    pool.checkin

    assert_raises Timeout::Error do
      Thread.new do
        pool.checkout
      end.join
    end

    pool.checkin

    assert Thread.new { pool.checkout }.join
  end

  def test_checkout
    pool = ConnectionPool.new(:size => 1) { NetworkConnection.new }

    conn = pool.checkout

    assert_kind_of NetworkConnection, conn

    assert_same conn, pool.checkout
  end

  def test_checkout_connection_args
    pool = ConnectionPool.new(:size => 1) { |host| NetworkConnection.new(host) }

    conn = pool.checkout 'a.example'

    assert_kind_of NetworkConnection, conn
    assert_equal 'a.example', conn.host

    assert_same conn, pool.checkout
  end

  def test_checkout_multithread
    pool = ConnectionPool.new(:size => 2) { NetworkConnection.new }
    conn = pool.checkout

    t = Thread.new do
      pool.checkout
    end

    refute_same conn, t.value
  end

  def test_checkout_timeout
    pool = ConnectionPool.new(:timeout => 0, :size => 0) { Object.new }

    assert_raises Timeout::Error do
      pool.checkout
    end
  end

  def test_checkout_timeout_override
    pool = ConnectionPool.new(:timeout => 0, :size => 1) { NetworkConnection.new }

    thread = Thread.new do
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    end

    Thread.pass while thread.status == 'run'

    assert_raises Timeout::Error do
      pool.checkout
    end

    assert pool.checkout :timeout => 0.1
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

    threads = Array.new(20) do
      Thread.new do
        pool.with do |net|
          sleep 0.01
        end
      end
    end

    threads.map { |thread| thread.join }
  end

  def test_reuses_objects_when_pool_not_saturated
    pool = ConnectionPool.new(:size => 5) { NetworkConnection.new }

    ids = 10.times.map do
      pool.with { |c| c.object_id }
    end

    assert_equal 1, ids.uniq.size
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

      Thread.pass

      r_outer.do_work('outer')
    end

    @other.join

    assert_equal ['inner', 'outer', 'other'], recorder.calls
  end

  def test_shutdown_is_executed_for_all_connections
    recorders = []

    pool = ConnectionPool.new(:size => 3) do
      Recorder.new.tap { |r| recorders << r }
    end

    use_pool pool, 3

    pool.shutdown do |recorder|
      recorder.do_work("shutdown")
    end

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_raises_error_after_shutting_down
    pool = ConnectionPool.new(:size => 1) { true }

    pool.shutdown { }

    assert_raises ConnectionPool::PoolShuttingDownError do
      pool.checkout
    end
  end

  def test_runs_shutdown_block_asynchronously_if_connection_was_in_use
    recorders = []

    pool = ConnectionPool.new(:size => 3) do
      Recorder.new.tap { |r| recorders << r }
    end

    use_pool pool, 3

    pool.checkout

    pool.shutdown do |recorder|
      recorder.do_work("shutdown")
    end

    assert_equal [[], ["shutdown"], ["shutdown"]], recorders.map { |r| r.calls }.sort

    pool.checkin

    assert_equal [["shutdown"], ["shutdown"], ["shutdown"]], recorders.map { |r| r.calls }
  end

  def test_raises_an_error_if_shutdown_is_called_without_a_block
    pool = ConnectionPool.new(:size => 1) { }

    assert_raises ArgumentError do
      pool.shutdown
    end
  end

  def test_shutdown_is_executed_for_all_connections_in_wrapped_pool
    recorders = []

    wrapper = ConnectionPool::Wrapper.new(:size => 3) do
      Recorder.new.tap { |r| recorders << r }
    end

    use_pool wrapper, 3

    wrapper.pool_shutdown do |recorder|
      recorder.do_work("shutdown")
    end

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_wrapper_method_missing
    wrapper = ConnectionPool::Wrapper.new { NetworkConnection.new }

    assert_equal 1, wrapper.fast
  end

  def test_wrapper_respond_to_eh
    wrapper = ConnectionPool::Wrapper.new { NetworkConnection.new }

    assert_respond_to wrapper, :with

    assert_respond_to wrapper, :fast
    refute_respond_to wrapper, :"nonexistent method"
  end

  def test_wrapper_with
    wrapper = ConnectionPool::Wrapper.new(:timeout => 0, :size => 1) { Object.new }

    wrapper.with do
      assert_raises Timeout::Error do
        Thread.new do
          wrapper.with { flunk 'connection checked out :(' }
        end.join
      end
    end

    assert Thread.new { wrapper.with { } }.join
  end

  def test_wrapper_with_connection_args
    wrapper = ConnectionPool::Wrapper.new(:timeout => 0, :size => 1) { Object.new }

    connection = nil

    wrapper.with('a.example') do |conn|
      connection = conn
    end

    assert connection
  end

  class ConnWithEval
    def eval(arg)
      "eval'ed #{arg}"
    end
  end

  def test_wrapper_kernel_methods
    wrapper = ConnectionPool::Wrapper.new(timeout: 0, size: 1) { ConnWithEval.new }

    assert_equal "eval'ed 1", wrapper.eval(1)
  end
end
