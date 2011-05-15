require 'thread'
require 'timeout'

class TimedQueue
  def initialize
    @que = []
    @mutex = Mutex.new
    @resource = ConditionVariable.new
  end

  def push(obj)
    @mutex.synchronize do
      @que.push obj
      @resource.signal
    end
  end
  alias_method :<<, :push

  def timed_pop(timeout=0.5)
    @mutex.synchronize do
      if @que.empty?
        @resource.wait(@mutex, timeout)
        raise Timeout::Error if @que.empty?
      end
      return @que.shift
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