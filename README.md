connection\_pool
=================
[![Build Status](https://travis-ci.org/mperham/connection_pool.svg)](https://travis-ci.org/mperham/connection_pool)

Generic connection pooling for Ruby. Originally forked from
[connection_pool](https://github.com/mperham/connection_pool), but with moderately different semantics.

MongoDB has its own connection pool.  ActiveRecord has its own connection pool.
This is a generic connection pool that can be used with anything, e.g. Redis,
Dalli and other Ruby network clients.


Usage
-----

Create a pool of objects to share amongst the fibers or threads in your Ruby
application:

```ruby
$memcached = ConnectionPool.new(
  size: 5,
  timeout: 5,
  connect: proc { Dalli::Client.new }
)
```

You can also pass your connection function as a block:

```ruby
$memcached = ConnectionPool.new(size: 5, timeout: 5) { Dalli::Client.new }
```

Or you can configure it later:

```ruby
$memcached = ConnectionPool.new(size: 5, timeout: 5)
$memcached.connect_with { Dalli::Client.new }
```

Then use the pool in your application:

``` ruby
$memcached.with do |conn|
  conn.get('some-count')
end
```

If all the objects in the connection pool are in use, `with` will block
until one becomes available.  If no object is available within `:timeout` seconds,
`with` will raise a `Timeout::Error`.

Optionally, you can specify a timeout override using the with-block semantics:

``` ruby
$memcached.with(timeout: 2.0) do |conn|
  conn.get('some-count')
end
```

This will only modify the resource-get timeout for this particular
invocation. This is useful if you want to fail-fast on certain non critical
sections when a resource is not available, or conversely if you are comfortable
blocking longer on a particular resource. This is not implemented in the below
`ConnectionPool::Wrapper` class.

## Migrating to a Connection Pool

You can use `ConnectionPool::Wrapper` to wrap a single global connection,
making it easier to migrate existing connection code over time:

``` ruby
$redis = ConnectionPool::Wrapper.new(size: 5, timeout: 3) { Redis.connect }
$redis.sadd('foo', 1)
$redis.smembers('foo')
```

The wrapper uses `method_missing` to checkout a connection, run the requested
method and then immediately check the connection back into the pool.  It's
**not** high-performance so you'll want to port your performance sensitive code
to use `with` as soon as possible.

``` ruby
$redis.with do |conn|
  conn.sadd('foo', 1)
  conn.smembers('foo')
end
```

Once you've ported your entire system to use `with`, you can simply remove
`Wrapper` and use the simpler and faster `ConnectionPool`.

## Thread-safety / Connection Multiplexing

`ConnectionPool`s are thread-safe and re-entrant in that the pool itself can be shared between different
threads and it is guaranteed that the same connection will never be returned from overlapping calls
to `#checkout` / `#with`. Note that this is achieved through the judicious use of mutexes; this code
is not appropriate for systems with hard real-time requiremnts. Then again, neither is Ruby.

The original `connection_pool` library had special functionality so that if you checked out
a connection from a thread which already had a checked out connection, you would be guaranteed
to get the same connection back again. This logic prevents a number of valable use cases,
so no longer exists. Each overlapping call to `pool.checkout` / `pool.with` will get a different
connection.

In particular, this feature could be abused to assume that adjacent calls to `Wrap`ed connections
from the same thread would go to the same database connection and perhaps the same session/transaction.
Don't do that. If you care about transactions or database sessions, you need to be explicitly checking
out and passing around connections.


## Shutdown

You can shut down a ConnectionPool instance once it should no longer be used.
Further checkout attempts will immediately raise an error but existing checkouts
will work.

```ruby
cp = ConnectionPool.new(
    connect: lambda { Redis.new },
    disconnect: lambda { |conn| conn.quit }
)
cp.shutdown
```

Shutting down a connection pool will block until all connections are checked in and closed.
**Note that shutting down is completely optional**; Ruby's garbage collector will reclaim
unreferenced pools under normal circumstances.

## Connection recycling

If you specify the `max_age` parameter to a connection pool, it will attempt to gracefully recycle
connections once they reach a certain age. This can be beneficial for, e.g., load balancers where you
want client applications to eventually pick up new databases coming into service without having to
explicitly restart the client processes.


Notes
-----

- Connections are lazily created as needed.
- There is no provision for repairing or checking the health of a connection;
  connections should be self-repairing.  This is true of the Dalli and Redis
  clients.
- **WARNING**: Don't ever use `Timeout.timeout` in your Ruby code or you will see
  occasional silent corruption and mysterious errors.  The Timeout API is unsafe
  and cannot be used correctly, ever.  Use proper socket timeout options as
  exposed by Net::HTTP, Redis, Dalli, etc.


Author
------

Originally by Mike Perham, [@mperham](https://twitter.com/mperham), <http://mikeperham.com>

Forked and modified by engineers at [EasyPost](https://www.easypost.com).
