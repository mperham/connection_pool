require_relative 'helper'

class TestConnectionPoolTimedStack < Minitest::Test

  def setup
    @manager = ConnectionPool::ConnectionManager.new(
      lambda { Object.new }
    )
    @stack = ConnectionPool::TimedStack.new(@manager, 0)
  end

  def test_empty_eh
    stack = ConnectionPool::TimedStack.new(@manager, 1)

    refute_empty stack

    popped = stack.pop

    assert_empty stack

    stack.push popped

    refute_empty stack
  end

  def test_length
    stack = ConnectionPool::TimedStack.new(@manager, 1)

    assert_equal 1, stack.length

    popped = stack.pop

    assert_equal 0, stack.length

    stack.push popped

    assert_equal 1, stack.length
  end

  def test_object_creation_fails
    @manager.connect_with do
      raise 'failure'
    end
    stack = ConnectionPool::TimedStack.new(@manager, 2)

    begin
      stack.pop
    rescue => error
      assert_equal 'failure', error.message
    end

    begin
      stack.pop
    rescue => error
      assert_equal 'failure', error.message
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
    e = assert_raises Timeout::Error do
      @stack.pop timeout: 0
    end

    assert_equal 'Waited 0 sec', e.message
  end

  def test_pop_empty_2_0_compatibility
    e = assert_raises Timeout::Error do
      @stack.pop 0
    end

    assert_equal 'Waited 0 sec', e.message
  end

  def test_pop_full
    stack = ConnectionPool::TimedStack.new(@manager, 1)

    popped = stack.pop

    refute_nil popped
    assert_empty stack
  end

  def test_pop_wait
    thread = Thread.start do
      @stack.pop
    end

    Thread.pass while thread.status == 'run'

    object = Object.new

    @stack.push object

    assert_same object, thread.value
  end

  def test_pop_shutdown
    @stack.shutdown { }

    assert_raises ConnectionPool::PoolShuttingDownError do
      @stack.pop
    end
  end

  def test_push
    stack = ConnectionPool::TimedStack.new(@manager, 1)

    conn = stack.pop

    stack.push conn

    refute_empty stack
  end

  def test_push_shutdown
    called = []

    @manager.disconnect_with do |object|
      called << object
    end

    @stack.shutdown

    @stack.push @manager.create_new

    refute_empty called
    assert_empty @stack
  end

  def test_shutdown
    @stack.push @manager.create_new

    called = []

    @manager.disconnect_with do |object|
      called << object
    end

    @stack.shutdown

    refute_empty called
    assert_empty @stack
  end

end

