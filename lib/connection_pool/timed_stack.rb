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

  def push(obj)
    @mutex.synchronize do
      if @shutdown_block
        @shutdown_block.call(obj)
      else
        store_connection obj
      end

      @resource.broadcast
    end
  end
  alias_method :<<, :push

  def pop(timeout=0.5)
    deadline = Time.now + timeout
    @mutex.synchronize do
      loop do
        raise ConnectionPool::PoolShuttingDownError if @shutdown_block
        return fetch_connection if connection_stored?

        connection = try_create
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

  def connection_stored? # :nodoc:
    !@que.empty?
  end

  def fetch_connection # :nodoc:
    @que.pop
  end

  def shutdown_connections # :nodoc:
    while connection_stored?
      conn = fetch_connection
      @shutdown_block.call(conn)
    end
  end

  def store_connection obj # :nodoc:
    @que.push obj
  end

  def try_create # :nodoc:
    unless @created == @max
      @created += 1
      @create_block.call
    end
  end
end
