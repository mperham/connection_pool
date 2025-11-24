require "bundler/setup"
Bundler.require(:default, :test)

require "minitest/pride"
require "maxitest/autorun"
require "maxitest/threads"

# $VERBOSE = 1
# $TESTING = true
# disable minitest/parallel threads
# ENV["MT_CPU"] = "0"
# ENV["N"] = "0"
# Disable any stupid backtrace cleansers
# ENV["BACKTRACE"] = "1"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    add_filter "/test/"
    minimum_coverage 90
  end
end

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
