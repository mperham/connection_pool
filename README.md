connection_pool
======================

Generic connection pooling for Ruby.

MongoDB has its own connection pool.  ActiveRecord has its own connection pool.  This is a generic connection pool that can be used with anything, e.g. Redis, Dalli and other Ruby network clients.

Install
------------

    gem install connection_pool

Usage
------------

Create a pool of objects to share amongst the fibers or threads in your Ruby application:

    @memcached = ConnectionPool.new(:size => 5, :timeout => 5) { Dalli::Client.new }

Then use the pool in your application:

    @memcached.with do |dalli|
      dalli.fetch('some-count', :expires_in => 1.day) do
        SomeModel.query.count
      end
    end


Author
--------------

Mike Perham, [@mperham](https://twitter.com/mperham), <http://mikeperham.com>