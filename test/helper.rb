gem "minitest"

require "minitest/pride"
require "minitest/autorun"

$VERBOSE = 1

require_relative "../lib/connection_pool"

class ConnectionPool
  def self.reset_instances
    silence_warnings do
      const_set(:INSTANCES, ObjectSpace::WeakMap.new)
    end
  end
end

def silence_warnings
  old, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = old
end
