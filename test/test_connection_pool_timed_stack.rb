require_relative 'helper'

class TestConnectionPoolTimedStack < Minitest::Test

  class Connection
    attr_reader :host

    def initialize(host)
      @host = host
    end
  end

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

  def test_pop
    object = Object.new
    @stack.push object

    popped = @stack.pop

    assert_same object, popped
  end

  def test_pop_empty
    e = assert_raises Timeout::Error do
      @stack.pop 0
    end

    assert_equal 'Waited 0 sec', e.message
  end

  def test_pop_full
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

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

  def test_pop_recycle
    stack = ConnectionPool::TimedStack.new(2) { |host| Connection.new(host) }

    a_conn = stack.pop nil, 'a.example'
    stack.push a_conn, 'a.example'

    b_conn = stack.pop nil, 'b.example'
    stack.push b_conn, 'b.example'

    c_conn = stack.pop nil, 'c.example'

    assert_equal 'c.example', c_conn.host

    stack.push c_conn, 'c.example'

    recreated = stack.pop nil, 'a.example'

    refute_same a_conn, recreated
  end

  def test_pop_shutdown
    @stack.shutdown { }

    assert_raises ConnectionPool::PoolShuttingDownError do
      @stack.pop
    end
  end

  def test_pop_type
    stack = ConnectionPool::TimedStack.new(2) { |host| Connection.new(host) }

    conn = stack.pop nil, 'a.example'

    assert_equal 'a.example', conn.host

    conn = stack.pop nil, 'b.example'

    assert_equal 'b.example', conn.host

    assert_raises Timeout::Error do
      conn = stack.pop 0, 'a.example'
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

  def test_push_type
    stack = ConnectionPool::TimedStack.new(1) { Object.new }

    conn = stack.pop nil, 'a'

    stack.push conn, 'a'

    refute_empty stack
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

end

