require 'connection_pool/version'
require 'connection_pool/exceptions'
require 'connection_pool/timed_stack'

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
  DEFAULTS = { :size => 5, :timeout => 5, :loading => :eager }

  def self.wrap(options, &block)
    Wrapper.new(options, &block)
  end

  def initialize(options = {}, &block)
    raise ArgumentError, 'Connection pool requires a block' unless block

    options = DEFAULTS.merge(options)

    @size            = options.fetch(:size)
    @timeout         = options.fetch(:timeout)
    @loading_pattern = options.fetch(:loading)

    @client_creation_block = block

    @available = TimedStack.new(@size, eager_loaded?, &block)
    @key       = :"current-#{@available.object_id}"
  end

  def with
    conn = checkout
    begin
      yield conn
    ensure
      checkin
    end
  end

  def checkout
    stack = ::Thread.current[@key] ||= []
    conn = if stack.empty?
      begin
        @available.pop(@timeout)
      rescue Timeout::Error
        raise Timeout::Error if eager_loaded?

        if @available.max_connections_reached?
          raise ConnectionPool::ConnectionPoolFullException
        else
          create_connection
        end
      rescue ConnectionPool::EmptyPoolException
        create_connection
      end
    else
      stack.last
    end
    stack.push conn
    conn
  end

  def checkin
    stack = ::Thread.current[@key]
    conn  = stack.pop
    @available << conn if stack.empty?
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
      yield @pool.checkout
    ensure
      @pool.checkin
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


  private

  def create_connection
    @available.increment_connection
    @client_creation_block.call
  end

  def eager_loaded?
    @loading_pattern == :eager
  end
end
