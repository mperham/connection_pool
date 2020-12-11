require_relative "../helper"

require "benchmark/ips"

n = 100_000

cp_block = ConnectionPool.new { Object.new }
cp_wrapped = ConnectionPool.wrap({}) { Object.new }

Benchmark.ips do |x|
  x.report('.new') do
    cp_block.with { |obj| obj.object_id }
  end
  x.report('.wrap') do
    cp_wrapped.object_id
  end
  x.compare!
end
