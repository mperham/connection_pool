class ConnectionPoolReaper

  def initialize(connection_pool:, reaping_frequency:, reap_after:)
    @reaping_frequency = reaping_frequency
    @reap_after = reap_after
    @reaping_thread = start_reaping_thread
    @connection_pool = connection_pool
    @access_log = {}
    @mutex = Mutex.new
  end

  def mark_connection_as_used(connection)
    @mutex.synchronize { @access_log[connection] = Time.now }
  end

  def reap_connections!
    @mutex.synchronize do
      required_last_access = Time.now - @reap_after

      to_remove = []

      @access_log.delete_if do |c, last_access|
        last_access < required_last_access && to_remove << c
      end

      to_remove.each do |connection|
        @connection_pool.remove_connection(connection)
        connection.close if connection.respond_to?(:close)
      end
    end
  end

  def shutdown
    @reaping_thread.exit if @reaping_thread
  end

  def start_reaping_thread
    Thread.new do
      loop do
        sleep @reaping_frequency
        reap_connections!
      end
    end
  end
end
