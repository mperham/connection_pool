class ConnectionPool::PoolShuttingDownError < RuntimeError; end

# Exception sent when fetching a value from an empty pool and there are still
# empty slots to fill
class ConnectionPool::EmptyPoolException < StandardError; end

# Exception sent when fetching the connection is empty and all of their
# connections are in use
class ConnectionPool::ConnectionPoolFullException < StandardError; end