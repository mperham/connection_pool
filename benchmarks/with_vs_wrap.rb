require_relative "../test/helper"

require "benchmark/ips"

cp_block = ConnectionPool.new { Object.new }
cp_wrapped = ConnectionPool.wrap(ConnectionPool::DEFAULTS) { Object.new }

Benchmark.ips do |x|
  x.report('with') do
    cp_block.with(&:object_id)
  end

  x.report('wrap') do
    cp_wrapped.object_id
  end

  x.compare!
end
