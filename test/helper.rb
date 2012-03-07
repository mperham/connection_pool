require 'rubygems'
require 'minitest/autorun'

require 'connection_pool'

puts RUBY_DESCRIPTION

class MiniTest::Unit::TestCase

  def async_test(time=0.5)
    q = ConnectionPool::TimedQueue.new
    yield Proc.new { q << nil }
    q.timed_pop(time)
  end

end
