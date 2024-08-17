require_relative "helper"

class TestConnectionPoolTimedStack < Minitest::Test
  def setup
    @stack = ConnectionPool::TimedStack.new { Object.new }
  end

  def test_empty_eh
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

    refute_empty stack

    popped = stack.pop

    assert_empty stack

    stack.push popped

    refute_empty stack
  end

  def test_length
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

    assert_equal 1, stack.length

    popped = stack.pop

    assert_equal 0, stack.length

    stack.push popped

    assert_equal 1, stack.length
  end

  def test_length_after_shutdown_reload_for_no_create_stack
    assert_equal 0, @stack.length

    @stack.push(Object.new)

    assert_equal 1, @stack.length

    @stack.shutdown(reload: true) {}

    assert_equal 0, @stack.length
  end

  def test_length_after_shutdown_reload_with_checked_out_conn
    stack = ConnectionPool::TimedStack.new(1) { Object.new }
    conn = stack.pop
    stack.shutdown(reload: true) {}
    assert_equal 0, stack.length
    stack.push(conn)
    assert_equal 1, stack.length
  end

  def test_idle
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

    assert_equal 0, stack.idle

    popped = stack.pop

    assert_equal 0, stack.idle

    stack.push popped

    assert_equal 1, stack.idle
  end

  def test_object_creation_fails
    stack = ConnectionPool::TimedStack.new(2) { raise "failure" }

    begin
      stack.pop
    rescue => error
      assert_equal "failure", error.message
    end

    begin
      stack.pop
    rescue => error
      assert_equal "failure", error.message
    end

    refute_empty stack
    assert_equal 2, stack.length
  end

  def test_pop
    object = Object.new
    @stack.push object

    popped = @stack.pop

    assert_same object, popped
  end

  def test_pop_empty
    e = assert_raises(ConnectionPool::TimeoutError) { @stack.pop timeout: 0 }
    assert_equal "Waited 0 sec, 0/0 available", e.message
  end

  def test_pop_empty_2_0_compatibility
    e = assert_raises(Timeout::Error) { @stack.pop 0 }
    assert_equal "Waited 0 sec, 0/0 available", e.message
  end

  def test_pop_full
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

    popped = stack.pop

    refute_nil popped
    assert_empty stack
  end

  def test_pop_full_with_extra_conn_pushed
    stack = ConnectionPool::TimedStack.new(1) { Object.new }
    popped = stack.pop

    stack.push(Object.new)
    stack.push(popped)

    assert_equal 2, stack.length

    stack.shutdown(reload: true) {}

    assert_equal 1, stack.length
    stack.pop
    assert_raises(ConnectionPool::TimeoutError) { stack.pop(0) }
  end

  def test_pop_wait
    thread = Thread.start {
      @stack.pop
    }

    Thread.pass while thread.status == "run"

    object = Object.new

    @stack.push object

    assert_same object, thread.value
  end

  def test_pop_shutdown
    @stack.shutdown {}

    assert_raises ConnectionPool::PoolShuttingDownError do
      @stack.pop
    end
  end

  def test_pop_shutdown_reload
    stack = ConnectionPool::TimedStack.new(1) { Object.new }
    object = stack.pop
    stack.push(object)

    stack.shutdown(reload: true) {}

    refute_equal object, stack.pop
  end

  def test_pop_raises_error_if_shutdown_reload_is_run_and_connection_is_still_in_use
    stack = ConnectionPool::TimedStack.new(1) { Object.new }
    stack.pop
    stack.shutdown(reload: true) {}
    assert_raises ConnectionPool::TimeoutError do
      stack.pop(0)
    end
  end

  def test_push
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

    conn = stack.pop

    stack.push conn

    refute_empty stack
  end

  def test_push_shutdown
    called = []

    @stack.shutdown do |object|
      called << object
    end

    @stack.push Object.new

    refute_empty called
    assert_empty @stack
  end

  def test_shutdown
    @stack.push Object.new

    called = []

    @stack.shutdown do |object|
      called << object
    end

    refute_empty called
    assert_empty @stack
  end

  def test_shutdown_can_be_called_after_error
    3.times { @stack.push Object.new }

    called = []
    closing_error = "error in closing connection"
    raise_error = true
    shutdown_proc = ->(conn) do
      called << conn
      if raise_error
        raise_error = false
        raise closing_error
      end
    end

    assert_raises(closing_error) do
      @stack.shutdown(&shutdown_proc)
    end

    assert_equal 1, called.size

    @stack.shutdown(&shutdown_proc)
    assert_equal 3, called.size
  end

  def test_reap_can_be_called_after_error
    3.times { @stack.push Object.new }

    called = []
    closing_error = "error in closing connection"
    raise_error = true
    reap_proc = ->(conn) do
      called << conn
      if raise_error
        raise_error = false
        raise closing_error
      end
    end

    assert_raises(closing_error) do
      @stack.reap(0, &reap_proc)
    end

    assert_equal 1, called.size

    @stack.reap(0, &reap_proc)
    assert_equal 3, called.size
  end

  def test_reap
    @stack.push Object.new

    called = []

    @stack.reap(0) do |object|
      called << object
    end

    refute_empty called
    assert_empty @stack
  end

  def test_reap_full_stack
    stack = ConnectionPool::TimedStack.new(1) { Object.new }
    stack.push stack.pop

    stack.reap(0) do |object|
      nil
    end

    # Can still pop from the stack after reaping all connections
    refute_nil stack.pop
  end

  def test_reap_large_idle_seconds
    @stack.push Object.new

    called = []

    @stack.reap(100) do |object|
      called << object
    end

    assert_empty called
    refute_empty @stack
  end

  def test_reap_no_block
    assert_raises(ArgumentError) do
      @stack.reap(0)
    end
  end

  def test_reap_non_numeric_idle_seconds
    assert_raises(ArgumentError) do
      @stack.reap("0") { |object| object }
    end
  end

  def test_reap_with_multiple_connections
    stack = ConnectionPool::TimedStack.new(2) { Object.new }
    stubbed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    conn1 = stack.pop
    conn2 = stack.pop

    stack.stub :current_time, stubbed_time do
      stack.push conn1
    end

    stack.stub :current_time, stubbed_time + 1 do
      stack.push conn2
    end

    called = []

    stack.stub :current_time, stubbed_time + 2 do
      stack.reap(1.5) do |object|
        called << object
      end
    end

    assert_equal [conn1], called
    refute_empty stack
    assert_equal 1, stack.idle
  end

  def test_reap_with_multiple_connections_and_zero_idle_seconds
    stack = ConnectionPool::TimedStack.new(2) { Object.new }
    stubbed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    conn1 = stack.pop
    conn2 = stack.pop

    stack.stub :current_time, stubbed_time do
      stack.push conn1
    end

    stack.stub :current_time, stubbed_time + 1 do
      stack.push conn2
    end

    called = []

    stack.stub :current_time, stubbed_time + 2 do
      stack.reap(0) do |object|
        called << object
      end
    end

    assert_equal [conn1, conn2], called
    assert_equal 0, stack.idle
  end

  def test_reap_with_multiple_connections_and_idle_seconds_outside_range
    stack = ConnectionPool::TimedStack.new(2) { Object.new }
    stubbed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    conn1 = stack.pop
    conn2 = stack.pop

    stack.stub :current_time, stubbed_time do
      stack.push conn1
    end

    stack.stub :current_time, stubbed_time + 1 do
      stack.push conn2
    end

    called = []

    stack.stub :current_time, stubbed_time + 2 do
      stack.reap(3) do |object|
        called << object
      end
    end

    assert_empty called
    assert_equal 2, stack.idle
  end
end
