class ConnectionPool
  class Wrapper < ::BasicObject
    METHODS = [:with, :pool_shutdown, :wrapped_pool]

    def initialize(**options, &block)
      @pool = options.fetch(:pool) { ::ConnectionPool.new(**options, &block) }
    end

    def wrapped_pool
      @pool
    end

    def with(**, &block)
      @pool.with(**, &block)
    end

    def pool_shutdown(&block)
      @pool.shutdown(&block)
    end

    def pool_size
      @pool.size
    end

    def pool_available
      @pool.available
    end

    def respond_to?(id, *, **)
      METHODS.include?(id) || with { |c| c.respond_to?(id, *, **) }
    end

    def respond_to_missing?(id, *, **)
      with { |c| c.respond_to?(id, *, **) }
    end

    def method_missing(name, *, **, &)
      with do |connection|
        connection.send(name, *, **, &)
      end
    end
  end
end
