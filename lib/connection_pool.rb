require 'connection_pool/version'
require 'timed_queue'

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
# Example usage replacing an existing connection (slower):
#
#    $redis = ConnectionPool.wrap { Redis.new }
#
#    def do_work
#      $redis.lpop('my-list') if $redis.llen('my-list') > 0
#    end
#
# Accepts the following options:
# - :size - number of connections to pool, defaults to 5
# - :timeout - amount of time to wait for a connection if none currently available, defaults to 5 seconds
#
class ConnectionPool
  DEFAULTS = { :size => 5, :timeout => 5 }

  def self.wrap(options, &block)
    Wrapper.new(options, &block)
  end

  def initialize(options={}, &block)
    raise ArgumentError, 'Connection pool requires a block' unless block

    options = DEFAULTS.merge(options)

    @size = options[:size] || DEFAULTS[:size]
    @timeout = options[:timeout] || DEFAULTS

    @available = ::TimedQueue.new(@size, &block)
    @key = :"current-#{@available.object_id}"
  end

  def with(&block)
    yield checkout
  ensure
    checkin
  end
  alias_method :with_connection, :with

  private

  def checkout
    ::Thread.current[@key] ||= @available.timed_pop(@timeout)
  end

  def checkin
    conn = ::Thread.current[@key]
    ::Thread.current[@key] = nil
    return unless conn
    @available << conn
    nil
  end

  class Wrapper < BasicObject
    def initialize(options = {}, &block)
      @pool = ::ConnectionPool.new(options, &block)
    end

    def method_missing(name, *args, &block)
      @pool.with do |connection|
        connection.send(name, *args, &block)
      end
    end
  end
end
