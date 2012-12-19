connection_pool
======================

Generic connection pooling for Ruby.

MongoDB has its own connection pool.  ActiveRecord has its own connection pool.  This is a generic connection pool that can be used with anything, e.g. Redis, Dalli and other Ruby network clients.


Install
------------

    gem install connection_pool


Notes
------------

- Connections are eager created when the pool is created.
- There is no provision for repairing or checking the health of a
  connection; connections should be self-repairing.  This is
true of the dalli and redis clients.


Usage
------------

Create a pool of objects to share amongst the fibers or threads in your Ruby application:

``` ruby
@memcached = ConnectionPool.new(:size => 5, :timeout => 5) { Dalli::Client.new }
```

Then use the pool in your application:

``` ruby
@memcached.with do |dalli|
  dalli.get('some-count')
end
```

If all the objects in the connection pool are in use, `with` will block
until one becomes available.  If no object is available within `:timeout` seconds,
`with` will raise a `Timeout::Error`.

You can use `ConnectionPool::Wrapper` to wrap a single global connection, making
it easier to port your connection code over time:

``` ruby
$redis = ConnectionPool::Wrapper.new(:size => 5, :timeout => 3) { Redis.connect }
$redis.sadd('foo', 1)
$redis.smembers('foo')
```

The Wrapper uses `method_missing` to checkout a connection, run the
requested method and then immediately check the connection back into the
pool.  It's **not** high-performance so you'll want to port your
performance sensitive code to use `with` as soon as possible.

``` ruby
$redis.with do |conn|
  conn.sadd('foo', 1)
  conn.smembers('foo')
end
```

Once you've ported your entire system to use `with`, you can simply
remove ::Wrapper and use a simple, fast ConnectionPool.

Author
--------------

Mike Perham, [@mperham](https://twitter.com/mperham), <http://mikeperham.com>
