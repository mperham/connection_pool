gem "minitest"

require "minitest/pride"
require "minitest/autorun"

$VERBOSE = 1

require_relative "../lib/connection_pool"

class Class
  def stub_const(const, value)
    ov, $VERBOSE = $VERBOSE
    const_set(const, value)
  ensure
    $VERBOSE = ov
  end
end
