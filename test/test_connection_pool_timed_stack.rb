Thread.abort_on_exception = true
require 'helper'

class TestConnectionPoolTimedStack < Minitest::Test

  def setup
    @stack = ConnectionPool::TimedStack.new { Object.new }
  end

  def test_empty_eh
    assert_empty @stack

    @stack.push Object.new

    refute_empty @stack
  end

  def test_length
    assert_equal 0, @stack.length

    @stack.push Object.new

    assert_equal 1, @stack.length
  end

  def test_pop
    e = assert_raises Timeout::Error do
      @stack.pop 0.0000001
    end

    assert_match %r%Waited [\de.-]+ sec%, e.message
  end

  def test_push
    assert_empty @stack

    @stack.push Object.new

    refute_empty @stack
  end

  def test_shutdown
    @stack.push Object.new

    called = []

    @stack.shutdown do |object|
      called << object
    end

    refute_empty called
    assert_empty @stack

    @stack.push Object.new

    assert_equal 2, called.length
    assert_empty @stack
  end

end

