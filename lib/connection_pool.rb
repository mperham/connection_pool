require 'connection_pool/timed_queue'

# Generic connection pool class for e.g. sharing a limited number of network connections
# among many threads.  Note: Connections are eager created.
#
# Example usage with block (faster):
#
#    @pool = ConnectionPool.new { Redis.new }
#
#    @pool.with do |redis|
#      redis.lpop('my-list') if redis.llen('my-list') > 0
#    end
#
# Example usage replacing a global connection (slower):
#
#    REDIS = ConnectionPool.new { Redis.new }
#
#    def do_work
#      REDIS.lpop('my-list') if REDIS.llen('my-list') > 0
#    end
#
# Accepts the following options:
# - :size - number of connections to pool, defaults to 5
# - :timeout - amount of time to wait for a connection if none currently available, defaults to 5 seconds
#
class ConnectionPool
  DEFAULTS = { :size => 5, :timeout => 5 }

  def initialize(options={})
    raise ArgumentError, 'Connection pool requires a block' unless block_given?

    @available = TimedQueue.new
    @options = DEFAULTS.merge(options)
    @options[:size].times do
      @available << yield
    end
    @busy = []
  end

  def with(&block)
    yield checkout
  ensure
    checkin
  end

  def method_missing(name, *args)
    checkout.send(name, *args)
  ensure
    checkin
  end

  private

  def checkout
    Thread.current[:"current-#{self.object_id}"] ||= begin
      conn = @available.timed_pop(@options[:timeout])
      @busy << conn
      conn
    end
  end

  def checkin
    conn = Thread.current[:"current-#{self.object_id}"]
    Thread.current[:"current-#{self.object_id}"] = nil
    @busy.delete(conn)
    @available << conn
    nil
  end

end