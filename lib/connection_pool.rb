require_relative 'connection_pool/version'
require_relative 'connection_pool/timed_stack'

# Generic connection pool class for e.g. sharing a limited number of network connections
# among many threads.  Note: Connections are lazily created.
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
    # Connections can become corrupted via Timeout::Error.  Discard
    # any connection whose usage after checkout does not finish as expected.
    # See #67
    success = false
    begin
      conn = checkout(options)
      result = yield conn
      success = true # means the connection wasn't interrupted
      result
    ensure
      if success
        # everything is roses, we can safely check the connection back in
        checkin
      else
        @available.discard!(pop_connection)
      end
    end
  end

  def checkout(options = {})
    # If we already have a connection checked out for this thread
    # we assume it's corrupted and should be discarded rather than reused
    if conn = ::Thread.current[@key]
      @available.discard!(conn)
      ::Thread.current[@key] = nil
    end

    timeout = options[:timeout] || @timeout
    ::Thread.current[@key] = @available.pop(timeout: timeout)
  end

  def checkin
    conn = pop_connection # mutates stack, must be on its own line
    @available.push(conn) if !::Thread.current[@key]

    nil
  end

  def shutdown(&block)
    @available.shutdown(&block)
  end

  private

  def pop_connection
    unless ::Thread.current[@key]
      raise ConnectionPool::Error, 'no connections are checked out'
    end

    conn = ::Thread.current[@key]
    ::Thread.current[@key] = nil
    conn
  end

  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown]

    def initialize(options = {}, &block)
      @pool = ::ConnectionPool.new(options, &block)
    end

    def with(&block)
      @pool.with(&block)
    end

    def pool_shutdown(&block)
      @pool.shutdown(&block)
    end

    def respond_to?(id, *args)
      METHODS.include?(id) || with { |c| c.respond_to?(id, *args) }
    end

    def method_missing(name, *args, &block)
      with do |connection|
        connection.send(name, *args, &block)
      end
    end
  end
end
