# -*- encoding: utf-8 -*-
require "./lib/connection_pool/version"

Gem::Specification.new do |s|
  s.name        = "connection_pool"
  s.version     = ConnectionPool::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Mike Perham"]
  s.email       = ["mperham@gmail.com"]
  s.homepage    = ""
  s.description = s.summary = %q{Generic connection pool for Ruby}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
