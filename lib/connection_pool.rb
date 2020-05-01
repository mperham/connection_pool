require_relative 'connection_pool/version'
require_relative 'connection_pool/timed_stack'
require_relative 'connection_pool/reaper'


# Generic connection pool class for sharing a limited number of objects or network connections
# among many threads.  Note: pool elements are lazily created.
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
#    @pool.with(timeout: 2.0) do |redis|
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
  DEFAULTS = {size: 5, timeout: 5, reaping_frequency: nil, reap_after: 60}

  class Error < RuntimeError
  end

  def self.wrap(options, &block)
    Wrapper.new(options, &block)
  end

  def initialize(options = {}, &block)
    raise ArgumentError, 'Connection pool requires a block' unless block

    options = DEFAULTS.merge(options)

    @size = Integer(options.fetch(:size))
    @timeout = options.fetch(:timeout)

    @available = TimedStack.new(@size, &block)
    @key = :"pool-#{@available.object_id}"
    @key_count = :"pool-#{@available.object_id}-count"

    if options[:reaping_frequency] && options[:reap_after]
      @reaper = ConnectionPoolReaper.new(
        connection_pool: self,
        reaping_frequency: options[:reaping_frequency],
        reap_after: options[:reap_after]
      )
    end
  end

  def with(options = {})
    Thread.handle_interrupt(Exception => :never) do
      conn = checkout(options)
      begin
        Thread.handle_interrupt(Exception => :immediate) do
          yield conn
        end
      ensure
        checkin
      end
    end
  end

  def checkout(options = {})
    connection = if ::Thread.current[@key]
                   ::Thread.current[@key_count] += 1
                   ::Thread.current[@key]
                 else
                   ::Thread.current[@key_count] = 1
                   ::Thread.current[@key] = @available.pop(options[:timeout] || @timeout)
                 end

    @reaper.mark_connection_as_used(connection) if defined?(@reaper)

    connection
  end

  def checkin
    if ::Thread.current[@key]
      if ::Thread.current[@key_count] == 1
        @available.push(::Thread.current[@key])
        ::Thread.current[@key] = nil
      else
        ::Thread.current[@key_count] -= 1
      end
    else
      raise ConnectionPool::Error, 'no connections are checked out'
    end

    nil
  end

  # Removes a connection from the pool and makes the space available again
  # connection may not currently be checked out of the queue.
  def remove_connection(conn)
    @available.remove_connection(conn)
  end

  def shutdown(&block)
    @reaper.shutdown if defined?(@reaper)
    @available.shutdown(&block)
  end

  # Size of this connection pool
  def size
    @size
  end

  # Number of pool entries available for checkout at this instant.
  def available
    @available.length
  end

  private

  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown, :wrapped_pool]

    def initialize(options = {}, &block)
      @pool = options.fetch(:pool) { ::ConnectionPool.new(options, &block) }
    end

    def wrapped_pool
      @pool
    end

    def with(&block)
      @pool.with(&block)
    end

    def pool_shutdown(&block)
      @pool.shutdown(&block)
    end

    def pool_size
      @pool.size
    end

    def pool_available
      @pool.available
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
