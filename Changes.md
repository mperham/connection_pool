2.1.3
------
- redis-namespace connections which respond to `redis` disconnect by invoking
  the method on the underlying connection.

2.1.2
------

- The connection\_pool will now close any connections which respond to
  `close` (Dalli) or `disconnect!` (Redis).  This ensures discarded connections
  from the fix in 2.1.1 are torn down ASAP and don't linger open.


2.1.1
------

- Work around a subtle race condition with code which uses `Timeout.timeout` and
  checks out a connection within the timeout block.  This might cause
  connections to get into a bad state and raise very odd errors. [tamird, #67]


2.1.0
------

- Refactoring to better support connection pool subclasses [drbrain,
  #55]
- `with` should return value of the last expression [#59]


2.0.0
-----

- The connection pool is now lazy.  Connections are created as needed
  and retained until the pool is shut down. [drbrain, #52]

1.2.0
-----

- Add `with(options)` and `checkout(options)`. [mattcamuto]
  Allows the caller to override the pool timeout.
```ruby
@pool.with(:timeout => 2) do |conn|
end
```

1.1.0
-----

- New `#shutdown` method (simao)

    This method accepts a block and calls the block for each
    connection in the pool. After calling this method, trying to get a
    connection from the pool raises `PoolShuttingDownError`.

1.0.0
-----

- `#with_connection` is now gone in favor of `#with`.

- We no longer pollute the top level namespace with our internal
`TimedStack` class.

0.9.3
--------

- `#with_connection` is now deprecated in favor of `#with`.

    A warning will be issued in the 0.9 series and the method will be
    removed in 1.0.

- We now reuse objects when possible.

    This means that under no contention, the same object will be checked
    out from the pool after subsequent calls to `ConnectionPool#with`.

    This change should have no impact on end user performance. If
    anything, it should be an improvement, depending on what objects you
    are pooling.

0.9.2
--------

- Fix reentrant checkout leading to early checkin.

0.9.1
--------

- Fix invalid superclass in version.rb

0.9.0
--------

- Move method\_missing magic into ConnectionPool::Wrapper (djanowski)
- Remove BasicObject superclass (djanowski)

0.1.0
--------

- More precise timeouts and better error message
- ConnectionPool now subclasses BasicObject so `method_missing` is more effective.
