gem "minitest"

require "minitest/pride"
require "minitest/autorun"

$VERBOSE = 1

require_relative "../lib/connection_pool"

class ConnectionPool
  def self.reset_instances
    ov, $VERBOSE = $VERBOSE
    const_set(:INSTANCES, ObjectSpace::WeakMap.new)
  ensure
    $VERBOSE = ov
  end
end
