require 'rubygems'
require 'minitest/pride'
require 'minitest/autorun'

require 'connection_pool'

class Minitest::Unit::TestCase

  def async_test(time=0.5)
    q = TimedQueue.new
    yield Proc.new { q << nil }
    q.timed_pop(time)
  end

end
