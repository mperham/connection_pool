require_relative "helper"

class TestConnectionPool < Minitest::Test
  class NetworkConnection
    SLEEP_TIME = 0.1

    def initialize
      @x = 0
    end

    def do_something(*_args, increment: 1)
      @x += increment
      sleep SLEEP_TIME
      @x
    end

    def do_something_with_positional_hash(options)
      @x += options[:increment] || 1
      sleep SLEEP_TIME
      @x
    end

    def fast
      @x += 1
    end

    def do_something_with_block
      @x += yield
      sleep SLEEP_TIME
      @x
    end

    def respond_to?(method_id, *args)
      method_id == :do_magic || super
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
    Array.new(size) {
      Thread.new do
        pool.with { sleep }
      end
    }.each do |thread|
      Thread.pass until thread.status == "sleep"
    end
  end

  def kill_threads(threads)
    threads.each do |thread|
      thread.kill
      thread.join
    end
  end

  def test_basic_multithreaded_usage
    pool_size = 5
    pool = ConnectionPool.new(size: pool_size) { NetworkConnection.new }

    start = Time.new

    generations = 3

    result = Array.new(pool_size * generations) {
      Thread.new do
        pool.with do |net|
          net.do_something
        end
      end
    }.map(&:value)

    finish = Time.new

    assert_equal((1..generations).cycle(pool_size).sort, result.sort)

    assert_operator(finish - start, :>, generations * NetworkConnection::SLEEP_TIME)
  end

  def test_timeout
    pool = ConnectionPool.new(timeout: 0, size: 1) { NetworkConnection.new }
    thread = Thread.new {
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    }

    Thread.pass while thread.status == "run"

    assert_raises Timeout::Error do
      pool.with { |net| net.do_something }
    end

    thread.join

    pool.with do |conn|
      refute_nil conn
    end
  end

  def test_with
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }

    pool.with do
      Thread.new {
        assert_raises Timeout::Error do
          pool.checkout
        end
      }.join
    end

    assert Thread.new { pool.checkout }.join
  end

  def test_then
    pool = ConnectionPool.new { Object.new }

    assert_equal pool.method(:then), pool.method(:with)
  end

  def test_with_timeout
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }

    assert_raises Timeout::Error do
      Timeout.timeout(0.01) do
        pool.with do |obj|
          assert_equal 0, pool.available
          sleep 0.015
        end
      end
    end
    assert_equal 1, pool.available
  end

  def test_invalid_size
    assert_raises ArgumentError, TypeError do
      ConnectionPool.new(timeout: 0, size: nil) { Object.new }
    end
    assert_raises ArgumentError, TypeError do
      ConnectionPool.new(timeout: 0, size: "") { Object.new }
    end
  end

  def test_handle_interrupt_ensures_checkin
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }
    def pool.checkout(options)
      sleep 0.015
      super
    end

    action = lambda do
      Timeout.timeout(0.01) do
        pool.with do |obj|
          # Timeout::Error will be triggered by any non-trivial Ruby code
          # executed here since it couldn't be raised during checkout.
          # It looks like setting a local variable does not trigger
          # the Timeout check in MRI 2.2.1.
          obj.tap { obj.hash }
        end
      end
    end

    assert_raises Timeout::Error, &action
    assert_equal 1, pool.available
  end

  def test_explicit_return
    pool = ConnectionPool.new(timeout: 0, size: 1) {
      mock = Minitest::Mock.new
      def mock.disconnect!
        raise "should not disconnect upon explicit return"
      end
      mock
    }

    pool.with do |conn|
      return true
    end
  end

  def test_with_timeout_override
    pool = ConnectionPool.new(timeout: 0, size: 1) { NetworkConnection.new }

    t = Thread.new {
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    }

    Thread.pass while t.status == "run"

    assert_raises Timeout::Error do
      pool.with { |net| net.do_something }
    end

    pool.with(timeout: 2 * NetworkConnection::SLEEP_TIME) do |conn|
      refute_nil conn
    end
  end

  def test_with_options
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }
    stack = pool.instance_variable_get(:@available)

    def stack.connection_stored?(opts)
      raise opts.to_s
    end

    options = { foo: 123 }
    e = assert_raises do
      pool.with(options) {}
    end

    assert_equal e.message, options.to_s
  end

  def test_checkin
    pool = ConnectionPool.new(timeout: 0, size: 1) { NetworkConnection.new }
    conn = pool.checkout

    Thread.new {
      assert_raises Timeout::Error do
        pool.checkout
      end
    }.join

    pool.checkin

    assert_same conn, Thread.new { pool.checkout }.value
  end

  def test_returns_value
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }
    assert_equal 1, pool.with { |o| 1 }
  end

  def test_checkin_never_checkout
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }

    e = assert_raises(ConnectionPool::Error) { pool.checkin }
    assert_equal "no connections are checked out", e.message
  end

  def test_checkin_no_current_checkout
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }

    pool.checkout
    pool.checkin

    assert_raises ConnectionPool::Error do
      pool.checkin
    end
  end

  def test_checkin_twice
    pool = ConnectionPool.new(timeout: 0, size: 1) { Object.new }

    pool.checkout
    pool.checkout

    pool.checkin

    Thread.new {
      assert_raises Timeout::Error do
        pool.checkout
      end
    }.join

    pool.checkin

    assert Thread.new { pool.checkout }.join
  end

  def test_checkout
    pool = ConnectionPool.new(size: 1) { NetworkConnection.new }

    conn = pool.checkout

    assert_kind_of NetworkConnection, conn

    assert_same conn, pool.checkout
  end

  def test_checkout_multithread
    pool = ConnectionPool.new(size: 2) { NetworkConnection.new }
    conn = pool.checkout

    t = Thread.new {
      pool.checkout
    }

    refute_same conn, t.value
  end

  def test_checkout_timeout
    pool = ConnectionPool.new(timeout: 0, size: 0) { Object.new }

    assert_raises Timeout::Error do
      pool.checkout
    end
  end

  def test_checkout_timeout_override
    pool = ConnectionPool.new(timeout: 0, size: 1) { NetworkConnection.new }

    thread = Thread.new {
      pool.with do |net|
        net.do_something
        sleep 0.01
      end
    }

    Thread.pass while thread.status == "run"

    assert_raises Timeout::Error do
      pool.checkout
    end

    assert pool.checkout timeout: 2 * NetworkConnection::SLEEP_TIME
  end

  def test_passthru
    pool = ConnectionPool.wrap(timeout: 2 * NetworkConnection::SLEEP_TIME, size: 1) { NetworkConnection.new }
    assert_equal 1, pool.do_something
    assert_equal 2, pool.do_something
    assert_equal 5, pool.do_something_with_block { 3 }
    assert_equal 6, pool.with { |net| net.fast }
    assert_equal 8, pool.do_something(increment: 2)
    assert_equal 10, pool.do_something_with_positional_hash({:increment => 2, :symbol_key => 3, "string_key" => 4})
  end

  def test_passthru_respond_to
    pool = ConnectionPool.wrap(timeout: 2 * NetworkConnection::SLEEP_TIME, size: 1) { NetworkConnection.new }
    assert pool.respond_to?(:with)
    assert pool.respond_to?(:do_something)
    assert pool.respond_to?(:do_magic)
    refute pool.respond_to?(:do_lots_of_magic)
  end

  def test_return_value
    pool = ConnectionPool.new(timeout: 2 * NetworkConnection::SLEEP_TIME, size: 1) { NetworkConnection.new }
    result = pool.with { |net|
      net.fast
    }
    assert_equal 1, result
  end

  def test_heavy_threading
    pool = ConnectionPool.new(timeout: 0.5, size: 3) { NetworkConnection.new }

    threads = Array.new(20) {
      Thread.new do
        pool.with do |net|
          sleep 0.01
        end
      end
    }

    threads.map { |thread| thread.join }
  end

  def test_reuses_objects_when_pool_not_saturated
    pool = ConnectionPool.new(size: 5) { NetworkConnection.new }

    ids = 10.times.map {
      pool.with { |c| c.object_id }
    }

    assert_equal 1, ids.uniq.size
  end

  def test_nested_checkout
    recorder = Recorder.new
    pool = ConnectionPool.new(size: 1) { recorder }
    pool.with do |r_outer|
      @other = Thread.new { |t|
        pool.with do |r_other|
          r_other.do_work("other")
        end
      }

      pool.with do |r_inner|
        r_inner.do_work("inner")
      end

      Thread.pass

      r_outer.do_work("outer")
    end

    @other.join

    assert_equal ["inner", "outer", "other"], recorder.calls
  end

  def test_shutdown_is_executed_for_all_connections
    recorders = []

    pool = ConnectionPool.new(size: 3) {
      Recorder.new.tap { |r| recorders << r }
    }

    threads = use_pool pool, 3

    pool.shutdown do |recorder|
      recorder.do_work("shutdown")
    end

    kill_threads(threads)

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_checkout_after_reload_cannot_create_new_connections_beyond_size
    pool = ConnectionPool.new(size: 1) { Object.new }
    threads = use_pool pool, 1
    pool.reload {}
    assert_raises ConnectionPool::TimeoutError do
      pool.checkout(timeout: 0)
    end
  ensure
    kill_threads(threads) if threads
  end

  def test_raises_error_after_shutting_down
    pool = ConnectionPool.new(size: 1) { true }

    pool.shutdown {}

    assert_raises ConnectionPool::PoolShuttingDownError do
      pool.checkout
    end
  end

  def test_runs_shutdown_block_asynchronously_if_connection_was_in_use
    recorders = []

    pool = ConnectionPool.new(size: 3) {
      Recorder.new.tap { |r| recorders << r }
    }

    threads = use_pool pool, 2

    pool.checkout

    pool.shutdown do |recorder|
      recorder.do_work("shutdown")
    end

    kill_threads(threads)

    assert_equal [["shutdown"], ["shutdown"], []], recorders.map { |r| r.calls }

    pool.checkin

    assert_equal [["shutdown"], ["shutdown"], ["shutdown"]], recorders.map { |r| r.calls }
  end

  def test_raises_an_error_if_shutdown_is_called_without_a_block
    pool = ConnectionPool.new(size: 1) {}

    assert_raises ArgumentError do
      pool.shutdown
    end
  end

  def test_shutdown_is_executed_for_all_connections_in_wrapped_pool
    recorders = []

    wrapper = ConnectionPool::Wrapper.new(size: 3) {
      Recorder.new.tap { |r| recorders << r }
    }

    threads = use_pool wrapper, 3

    wrapper.pool_shutdown do |recorder|
      recorder.do_work("shutdown")
    end

    kill_threads(threads)

    assert_equal [["shutdown"]] * 3, recorders.map { |r| r.calls }
  end

  def test_reap_removes_idle_connections
    recorders = []
    pool = ConnectionPool.new(size: 1) do
      Recorder.new.tap { |r| recorders << r }
    end

    pool.with { |conn| conn }

    assert_equal 1, pool.idle

    pool.reap(0) { |recorder| recorder.do_work("reap") }

    assert_equal 0, pool.idle
    assert_equal [["reap"]], recorders.map(&:calls)
  end

  def test_reap_removes_all_idle_connections
    recorders = []
    pool = ConnectionPool.new(size: 3) do
      Recorder.new.tap { |r| recorders << r }
    end
    threads = use_pool(pool, 3)
    kill_threads(threads)

    assert_equal 3, pool.idle

    pool.reap(0) { |recorder| recorder.do_work("reap") }

    assert_equal 0, pool.idle
    assert_equal [["reap"]] * 3, recorders.map(&:calls)
  end

  def test_reap_does_not_remove_connections_if_outside_idle_time
    pool = ConnectionPool.new(size: 1) { Object.new }

    pool.with { |conn| conn }

    pool.reap(1000) { |conn| flunk "should not reap active connection" }
  end

  def test_idle_returns_number_of_idle_connections
    pool = ConnectionPool.new(size: 1) { Object.new }

    assert_equal 0, pool.idle

    pool.checkout

    assert_equal 0, pool.idle

    pool.checkin

    assert_equal 1, pool.idle
  end

  def test_idle_with_multiple_connections
    pool = ConnectionPool.new(size: 3) { Object.new }

    assert_equal 0, pool.idle

    threads = use_pool(pool, 3)

    assert_equal 0, pool.idle

    kill_threads(threads)

    assert_equal 3, pool.idle
  end

  def test_reap_raises_error_after_shutting_down
    pool = ConnectionPool.new(size: 1) { true }

    pool.shutdown {}

    assert_raises ConnectionPool::PoolShuttingDownError do
      pool.reap(0) {}
    end
  end

  def test_wrapper_wrapped_pool
    wrapper = ConnectionPool::Wrapper.new { NetworkConnection.new }
    assert_equal ConnectionPool, wrapper.wrapped_pool.class
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
    wrapper = ConnectionPool::Wrapper.new(timeout: 0, size: 1) { Object.new }

    wrapper.with do
      Thread.new {
        assert_raises Timeout::Error do
          wrapper.with { flunk "connection checked out :(" }
        end
      }.join
    end

    assert Thread.new { wrapper.with {} }.join
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

  def test_wrapper_with_connection_pool
    recorder = Recorder.new
    pool = ConnectionPool.new(size: 1) { recorder }
    wrapper = ConnectionPool::Wrapper.new(pool: pool)

    pool.with { |r| r.do_work("with") }
    wrapper.do_work("wrapped")

    assert_equal ["with", "wrapped"], recorder.calls
  end

  def test_stats_without_active_connection
    pool = ConnectionPool.new(size: 2) { NetworkConnection.new }

    assert_equal(2, pool.size)
    assert_equal(2, pool.available)
  end

  def test_stats_with_active_connection
    pool = ConnectionPool.new(size: 2) { NetworkConnection.new }

    pool.with do
      assert_equal(1, pool.available)
    end
  end

  def test_stats_with_string_size
    pool = ConnectionPool.new(size: "2") { NetworkConnection.new }

    pool.with do
      assert_equal(2, pool.size)
      assert_equal(1, pool.available)
    end
  end

  def test_after_fork_callback
    skip("MRI feature") unless Process.respond_to?(:fork)
    GC.start # cleanup instances created by other tests

    pool = ConnectionPool.new(size: 2) { NetworkConnection.new }
    prefork_connection = pool.with { |c| c }
    assert_equal(prefork_connection, pool.with { |c| c })
    ConnectionPool.after_fork
    refute_equal(prefork_connection, pool.with { |c| c })
  end

  def test_after_fork_callback_being_skipped
    skip("MRI feature") unless Process.respond_to?(:fork)
    GC.start # cleanup instances created by other tests

    pool = ConnectionPool.new(size: 2, auto_reload_after_fork: false) { NetworkConnection.new }
    prefork_connection = pool.with { |c| c }
    assert_equal(prefork_connection, pool.with { |c| c })
    ConnectionPool.after_fork
    assert_equal(prefork_connection, pool.with { |c| c })
  end

  def test_after_fork_callback_checkin
    skip("MRI feature") unless Process.respond_to?(:fork)
    GC.start # cleanup instances created by other tests

    pool = ConnectionPool.new(size: 2) { NetworkConnection.new }
    prefork_connection = pool.checkout
    assert_equal(prefork_connection, pool.checkout)
    ConnectionPool.after_fork
    refute_equal(prefork_connection, pool.checkout)
  end

  def test_automatic_after_fork_callback
    skip("MRI 3.1 feature") unless Process.respond_to?(:_fork)
    GC.start # cleanup instances created by other tests

    pool = ConnectionPool.new(size: 2) { NetworkConnection.new }
    prefork_connection = pool.with { |c| c }
    assert_equal(prefork_connection, pool.with { |c| c })
    pid = fork do
      refute_equal(prefork_connection, pool.with { |c| c })
      exit!(0)
    end
    assert_equal(prefork_connection, pool.with { |c| c })
    _, status = Process.waitpid2(pid)
    assert_predicate(status, :success?)
  end
end
