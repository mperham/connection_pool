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
