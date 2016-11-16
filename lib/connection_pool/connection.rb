require_relative 'monotonic_time'


class ConnectionPool::Connection
  attr_reader :conn

  def initialize(conn, max_age, shutdown_proc)
    @conn = conn
    @max_age = max_age
    @created_at = ConnectionPool.monotonic_time
    @shutdown_proc = shutdown_proc
  end

  # Shut down the connection. Can no longer be used after this!
  def shutdown!
    @shutdown_proc.call(@conn)
  end

  def expired?
    if @max_age.nil?
      false
    else
      (ConnectionPool.monotonic_time - @created_at) > @max_age
    end
  end
end
