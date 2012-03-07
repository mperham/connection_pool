require 'connection_pool_basic_object'
require 'thread'
require 'timeout'

class ConnectionPool < ConnectionPoolBasicObject
  class TimedQueue
    def initialize
      @que = []
      @mutex = Mutex.new
      @resource = ConditionVariable.new
    end

    def push(obj)
      @mutex.synchronize do
        @que.push obj
        @resource.broadcast
      end
    end
    alias_method :<<, :push

    def timed_pop(timeout=0.5)
      deadline = Time.now + timeout
      @mutex.synchronize do
        loop do
          return @que.shift unless @que.empty?
          to_wait = deadline - Time.now
          if RUBY_VERSION >= '1.9'
            raise Timeout::Error, "Waited #{timeout} sec" if to_wait <= 0
            @resource.wait(@mutex, to_wait)
          else
            Timeout.timeout(to_wait) { @resource.wait(@mutex) }
          end
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
end
