require 'thread'
require 'timeout'

class ConnectionPool::PoolShuttingDownError < RuntimeError
end

class ConnectionPool::TimedStack
  def initialize(size = 0)
    @que = Array.new(size) { yield }
    @mutex = Mutex.new
    @resource = ConditionVariable.new
    @shutdown_block = nil
  end

  def push(obj)
    @mutex.synchronize do
      if @shutdown_block
        @shutdown_block.call(obj)
      else
        @que.push obj
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
        return @que.pop unless @que.empty?
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

      @que.size.times do
        conn = @que.pop
        block.call(conn)
      end
    end
  end

  def empty?
    @que.empty?
  end

  def clear
    @que.clear
  end

  def length
    @que.length
  end
end
