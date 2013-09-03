require 'thread'
require 'timeout'

class ConnectionPool::TimedStack

  def initialize(size = 0, eager_loading = true, &block)
    @que                   = eager_loading ? Array.new(size) { yield } : []
    @mutex                 = Mutex.new
    @resource              = ConditionVariable.new
    @shutdown_block        = nil
    @max_size              = size
    @eager_loading         = eager_loading
    @existing_conns_count  = eager_loading ? size : 0
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

  def pop(timeout = 0.5)
    deadline  = Time.now + timeout
    @mutex.synchronize do
      loop do
        raise ConnectionPool::PoolShuttingDownError if @shutdown_block

        if @eager_loading
          return @que.pop unless empty?
        else
          if empty?
            raise(ConnectionPool::EmptyPoolException) unless max_connections_reached?
          else
            return @que.pop
          end
        end

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

  def increment_connection
    @existing_conns_count += 1
  end

  def max_connections_reached?
    @existing_conns_count == @max_size
  end

  def empty?
    @que.empty?
  end

  def length
    @que.length
  end
end
