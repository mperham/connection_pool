require 'thread'
require 'timeout'

class ConnectionPool::PoolShuttingDownError < RuntimeError; end

class ConnectionPool::TimedStack
  attr_accessor :creator

  def initialize(size = 0, &block)
    @que = Array.new(size) { yield }
    @creator = block
    @mutex = Mutex.new
    @resource = ConditionVariable.new
    @shutdown_block = nil
  end

  def shutdown(&block)
    raise ArgumentError, "shutdown must receive a block" unless block_given?

    @mutex.synchronize do
      @shutdown_block = block
      @resource.broadcast

      self.each { |conn| block.call(conn) }
    end
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

  def empty?
    @que.empty?
  end

  def length
    @que.length
  end
  alias_method :size, :length

  def count(*args, &block)
    @que.count(*args, &block)
  end

  def resize(new_size)
    if new_size > size
      difference = new_size - size
      difference.times do
        conn = creator.call
        yield conn if block_given?
        @que.push(conn)
      end

    elsif new_size < size
      difference = size - new_size
      difference.times do
        conn = @que.pop
        yield conn if block_given?
      end
    end

    size
  end
  alias_method :size=, :resize

  def each(&block)
    return Enumerator.new(self, :each) unless block_given?

    stack = []
    begin
      size.times do
        block.call(conn = @que.pop)
        stack << conn
      end
      stack.size.times {@que << stack.pop}
    end
    @que
  end
end
