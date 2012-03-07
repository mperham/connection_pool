connection_pool
======================

Generic connection pooling for Ruby.

MongoDB has its own connection pool.  ActiveRecord has its own connection pool.  This is a generic connection pool that can be used with anything, e.g. Redis, Dalli and other Ruby network clients.

Requirements
--------------

connection_pool is tested with MRI 1.8, MRI 1.9, JRuby 1.6.7+, and possibly others.

Install
------------

    gem install connection_pool

Usage
------------

Create a pool of objects to share amongst the fibers or threads in your Ruby application:

    @memcached = ConnectionPool.new(:size => 5, :timeout => 5) { Dalli::Client.new }

Then use the pool in your application:

    @memcached.with_connection do |dalli|
      dalli.get('some-count')
    end


Author
--------------

Mike Perham, [@mperham](https://twitter.com/mperham), <http://mikeperham.com>
