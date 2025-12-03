require "bundler/gem_tasks"
require "standard/rake"
require "rake/testtask"
Rake::TestTask.new

task default: [:"standard:fix", :test]

task :bench do
  require_relative "test/benchmarks"
end
