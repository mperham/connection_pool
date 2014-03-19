require 'thread'
require 'timeout'

class ConnectionPool::PoolShuttingDownError < RuntimeError; end

class ConnectionPool::TimedStack

  def initialize(size = 0, &block)
    @create_block = block
    @created = 0
    @que = []
    @max = size
    @mutex = Mutex.new
    @resource = ConditionVariable.new
    @shutdown_block = nil
  end

  def push(obj, options = {})
    @mutex.synchronize do
      if @shutdown_block
        @shutdown_block.call(obj)
      else
        store_connection obj, options
      end

      @resource.broadcast
    end
  end
  alias_method :<<, :push

  def pop(options = {})
    timeout = options.fetch :timeout, 0.5
    deadline = Time.now + timeout
    @mutex.synchronize do
      loop do
        raise ConnectionPool::PoolShuttingDownError if @shutdown_block
        return fetch_connection(options) if connection_stored?(options)

        connection = try_create(options)
        return connection if connection

        to_wait = deadline - Time.now
        raise Timeout::Error, "Waited #{timeout} sec" if to_wait <= 0
        @resource.wait(@mutex, to_wait)
      end
    end
  end

  def shutdown(&block)
    raise ArgumentError, "shutdown must receive a block" unless block_given?

    @mutex.synchronize do
      @shutdown_block = block
      @resource.broadcast

      shutdown_connections
    end
  end

  def empty?
    (@created - @que.length) >= @max
  end

  def length
    @max - @created + @que.length
  end

  private

  def connection_stored?(options = nil) # :nodoc:
    !@que.empty?
  end

  def fetch_connection(options = nil) # :nodoc:
    @que.pop
  end

  def shutdown_connections(options = nil) # :nodoc:
    while connection_stored?(options)
      conn = fetch_connection(options)
      @shutdown_block.call(conn)
    end
  end

  def store_connection(obj, options = nil) # :nodoc:
    @que.push obj
  end

  def try_create(options = nil) # :nodoc:
    unless @created == @max
      @created += 1
      @create_block.call
    end
  end
end
