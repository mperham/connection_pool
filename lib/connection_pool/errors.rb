require "timeout"

class ConnectionPool
  class Error < RuntimeError; end
  class ConnectionPool::PoolShuttingDownError < ConnectionPool::Error; end
  class ConnectionPool::TimeoutError < Timeout::Error; end
end
