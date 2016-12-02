require 'thread'
require 'timeout'
require_relative 'monotonic_time'

##
# Raised when you attempt to retrieve a connection from a pool that has been
# shut down.

class ConnectionPool::PoolShuttingDownError < RuntimeError; end


##
# The TimedStack manages a pool of homogeneous connections (or any resource
# you wish to manage).  Connections are created lazily up to a given maximum
# number.

# Examples:
#
#    ts = TimedStack.new(1) { MyConnection.new }
#
#    # fetch a connection
#    conn = ts.pop
#
#    # return a connection
#    ts.push conn
#
#    conn = ts.pop
#    ts.pop timeout: 5
#    #=> raises Timeout::Error after 5 seconds

class ConnectionPool::TimedStack

  ##
  # Creates a new pool with +size+ connections that are created by
  # constructing the given +connection_wrapper+ class

  def initialize(connection_manager, size = 0)
    @created = 0
    @que = []
    @max = size
    @mutex = Mutex.new
    @resource = ConditionVariable.new
    @connection_manager = connection_manager
    @shutting_down = false
  end

  ##
  # Returns +obj+ to the stack.  +options+ is ignored in TimedStack but may be
  # used by subclasses that extend TimedStack.

  def push(wrapper, options = {})
    @mutex.synchronize do
      if @shutting_down
        wrapper.shutdown!
      else
        store_connection wrapper, options
      end

      @resource.broadcast
    end
  end
  alias_method :<<, :push

  ##
  # Retrieves a connection from the stack.  If a connection is available it is
  # immediately returned.  If no connection is available within the given
  # timeout a Timeout::Error is raised.
  #
  # +:timeout+ is the only checked entry in +options+ and is preferred over
  # the +timeout+ argument (which will be removed in a future release).  Other
  # options may be used by subclasses that extend TimedStack.

  def pop(timeout = 0.5, options = {})
    options, timeout = timeout, 0.5 if Hash === timeout
    timeout = options.fetch :timeout, timeout

    deadline = ConnectionPool.monotonic_time + timeout
    @mutex.synchronize do
      loop do
        raise ConnectionPool::PoolShuttingDownError if @shutting_down
        return fetch_connection(options) if connection_stored?(options)

        connection = try_create(options)
        return connection if connection

        to_wait = deadline - ConnectionPool.monotonic_time
        raise Timeout::Error, "Waited #{timeout} sec" if to_wait <= 0
        @resource.wait(@mutex, to_wait)
      end
    end
  end

  ##
  # Mark a connection as abandoned so that it cannot be used again.
  # Will call the pre-configured shutdown proc, if provided.
  #
  def abandon(connection_wrapper)
    @mutex.synchronize do
      connection_wrapper.shutdown!
      @created -= 1
    end
  end

  ##
  # Shuts down the TimedStack which prevents connections from being checked
  # out. Calls the shutdown program specified in the ConnectionPool
  # initializer

  def shutdown()
    @mutex.synchronize do
      @shutting_down = true
      @resource.broadcast

      shutdown_connections
    end
  end

  ##
  # Returns +true+ if there are no available connections.

  def empty?
    (@created - @que.length) >= @max
  end

  ##
  # The number of connections available on the stack.

  def length
    @max - @created + @que.length
  end

  ##
  # Pre-create all possible connections
  def fill
    while add_one
    end
  end

  ##
  # Add one connection to the queue
  #
  # Returns true iff a connection was successfully created
  def add_one
    connection = try_create
    if connection.nil?
      false
    else
      push(connection)
      true
    end
  end

  private

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must returns true if a connection is available on the stack.

  def connection_stored?(options = nil)
    !@que.empty?
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must return a connection from the stack.

  def fetch_connection(options = nil)
    @que.pop
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must shut down all connections on the stack.

  def shutdown_connections(options = nil)
    while connection_stored?(options)
      conn = fetch_connection(options)
      conn.shutdown!
    end
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must return +obj+ to the stack.

  def store_connection(obj, options = nil)
    @que.push obj
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must create a connection if and only if the total number of
  # connections allowed has not been met.

  def try_create(options = nil)
    unless @created == @max
      object = @connection_manager.create_new()
      @created += 1
      object
    end
  end
end
