# frozen_string_literal: true

require_relative "helper"

class TestTimedStackSubclassing < Minitest::Test
  def setup
    @klass = Class.new(ConnectionPool::TimedStack)
  end

  def test_try_fetch_connection
    obj = Object.new
    stack = @klass.new(size: 1) { obj }
    assert_equal false, stack.send(:try_fetch_connection)
    assert_equal obj, stack.pop
    stack.push obj
    assert_equal obj, stack.send(:try_fetch_connection)
  end

  def test_override_try_fetch_connection
    obj = Object.new

    stack = @klass.new(size: 1) { obj }
    stack.push stack.pop

    connection_stored_called = "cs_called"
    stack.define_singleton_method(:connection_stored?) { |*| raise connection_stored_called }
    e = assert_raises { stack.send(:try_fetch_connection) }
    assert_equal connection_stored_called, e.message

    stack.define_singleton_method(:try_fetch_connection) { fetch_connection }
    assert_equal obj, stack.send(:try_fetch_connection)
  end
end
