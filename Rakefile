require 'bundler/gem_tasks'

require 'rake/testtask'
Rake::TestTask.new

require 'rubocop/rake_task'
RuboCop::RakeTask.new

task :default => [:test, :rubocop]
