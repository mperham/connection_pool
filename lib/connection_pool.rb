require_relative 'connection_pool/version'
require_relative 'connection_pool/timed_stack'

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
# Using optional timeout override (for that single invocation)
#
#    @pool.with(:timeout => 2.0) do |redis|
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
  DEFAULTS = {size: 5, timeout: 5}

  class Error < RuntimeError
  end

  def self.wrap(options, &block)
    Wrapper.new(options, &block)
  end

  def initialize(options = {}, &block)
    raise ArgumentError, 'Connection pool requires a block' unless block

    options = DEFAULTS.merge(options)

    @size = options.fetch(:size)
    @timeout = options.fetch(:timeout)

    @available = TimedStack.new(@size, &block)
    @key = :"current-#{@available.object_id}"
  end

  def with(options = {})
    conn = checkout(options)
    begin
      yield conn
    ensure
      checkin
    end
  end

  def checkout(options = {})
    stack = ::Thread.current[@key] ||= []

    if stack.empty?
      timeout = options[:timeout] || @timeout
      conn = @available.pop(timeout)
    else
      conn = stack.last
    end

    stack.push conn
    conn
  end

  def checkin
    stack = ::Thread.current[@key]
    raise ConnectionPool::Error, 'no connections are checked out' if
      !stack || stack.empty?

    conn = stack.pop
    if stack.empty?
      @available << conn
    end
    nil
  end

  def shutdown(&block)
    @available.shutdown(&block)
  end

  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown]

    def initialize(options = {}, &block)
      @pool = ::ConnectionPool.new(options, &block)
    end

    def with
      conn = @pool.checkout
      begin
        yield conn
      ensure
        @pool.checkin
      end
    end

    def pool_shutdown(&block)
      @pool.shutdown(&block)
    end

    def respond_to?(id, *args)
      METHODS.include?(id) || @pool.with { |c| c.respond_to?(id, *args) }
    end

    def method_missing(name, *args, &block)
      @pool.with do |connection|
        connection.send(name, *args, &block)
      end
    end
  end
end
