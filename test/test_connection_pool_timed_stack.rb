Thread.abort_on_exception = true
require 'helper'

class TestConnectionPoolTimedStack < Minitest::Test

  def setup
    @stack = ConnectionPool::TimedStack.new { Object.new }
  end

  def test_push
    assert_empty @stack

    @stack.push Object.new

    refute_empty @stack
  end

end

