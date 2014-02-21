require 'thread'
require 'timeout'

class ConnectionPool::PoolShuttingDownError < RuntimeError; end

class ConnectionPool::TimedStack

  def initialize(size = 0, &block)
    @create_block = block
    @created = 0
    @enqueued = 0
    @ques = Hash.new { |h, k| h[k] = [] }
    @max = size
    @mutex = Mutex.new
    @resource = ConditionVariable.new
    @shutdown_block = nil
  end

  def push(obj, connection_args = nil)
    @mutex.synchronize do
      if @shutdown_block
        @shutdown_block.call(obj)
      else
        @ques[connection_args].push obj
        @enqueued += 1
      end

      @resource.broadcast
    end
  end
  alias_method :<<, :push

  def pop(timeout=0.5, connection_args = nil)
    timeout ||= 0.5
    deadline = Time.now + timeout
    @mutex.synchronize do
      loop do
        raise ConnectionPool::PoolShuttingDownError if @shutdown_block
        unless @ques[connection_args].empty?
          @enqueued -= 1
          return @ques[connection_args].pop
        end
        unless @created == @max
          @created += 1
          return @create_block.call(connection_args)
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

      @ques.each do |key, conns|
        until conns.empty?
          conn = conns.pop
          @enqueued -= 1
          block.call(conn)
        end
      end
    end
  end

  def empty?
    (@created - @enqueued) >= @max
  end

  def length
    @max - @created + @enqueued
  end
end
