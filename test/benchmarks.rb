# bundle exec ruby test/benchmarks.rb
require "benchmark/ips"
require "connection_pool"

puts "ConnectionPool #{ConnectionPool::VERSION}"
CP = ConnectionPool.new { Object.new }

Benchmark.ips do |x|
  x.report("ConnectionPool#with") do
    CP.with {|x| }
  end
end