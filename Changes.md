x.x.x
--------

- Compatible with Ruby 1.8
- Defines ConnectionPool::TimedQueue instead of claiming the top-level ::TimedQueue

0.1.0
--------

- More precise timeouts and better error message
- ConnectionPool now subclasses BasicObject so `method_missing` is more effective.
