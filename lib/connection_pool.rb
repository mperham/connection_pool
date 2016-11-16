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
# - :max_age - maximum number of seconds that a connection may be alive for (will recycle on checkin/checkout)
# - :shutdown_proc - callable for shutting down a connection. can be overridden by passing a block to .shutdown()
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
    max_age = options.fetch(:max_age, Float::INFINITY)
    @shutdown_proc = options.fetch(:shutdown_proc, nil)

    if max_age.finite? && @shutdown_proc.nil?
      raise ArgumentError("If passing :max_age, then :shutdown_proc must not be nil (pass `lambda { |conn| }` to just use the garbage collector)")
    end

    @available = TimedStack.new(@size, max_age, @shutdown_proc, &block)
    @key = :"current-#{@available.object_id}"
  end

if Thread.respond_to?(:handle_interrupt)

  # MRI
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

else

  # jruby 1.7.x
  def with(options = {})
    conn = checkout(options)
    begin
      yield conn
    ensure
      checkin
    end
  end

end

  def checkout(options = {})
    conn_wrapper = if stack.empty?
       cr = nil
      loop do
        timeout = options[:timeout] || @timeout
        cr = @available.pop(timeout: timeout)
        if cr.expired?
          cr.shutdown!
        else
          break
        end
      end
      cr
    else
      stack.last
    end

    stack.push conn_wrapper
    conn_wrapper.conn
  end

  def checkin
    conn_wrapper = pop_connection # mutates stack, must be on its own line
    if stack.empty?
      if conn_wrapper.expired?
        conn_wrapper.shutdown!
      else
        @available.push(conn_wrapper)
      end
    end
    nil
  end

  def shutdown(&block)
    if block_given?
      shutdown_proc = block
    else
      shutdown_proc = @shutdown_proc
    end
    @available.shutdown(&shutdown_proc)
  end

  private

  def pop_connection
    if stack.empty?
      raise ConnectionPool::Error, 'no connections are checked out'
    else
      stack.pop
    end
  end

  def stack
    ::Thread.current[@key] ||= []
  end

  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown]

    def initialize(options = {}, &block)
      @pool = options.fetch(:pool) { ::ConnectionPool.new(options, &block) }
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
