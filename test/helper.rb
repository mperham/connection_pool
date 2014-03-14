gem 'minitest'

require 'minitest/pride'
require 'minitest/autorun'

Thread.abort_on_exception = true

$VERBOSE = 1

require_relative '../lib/connection_pool'
