# http://railstips.org/blog/archives/2009/08/07/patterns-are-not-scary-method-missing-proxy/
# We're defining ConnectionPoolBasicObject, not ConnectionPool::BasicObject, because ConnectionPool is going to subclass it.
if defined?(BasicObject)
  ConnectionPoolBasicObject = BasicObject
else
  # We must be in 1.8.
  # Still, don't define BasicObject (or BlankSlate) in case somebody else is relying on the presence or absence of that definition.
  class ConnectionPoolBasicObject #:nodoc:
    instance_methods.each { |m| undef_method m unless m =~ /^__|instance_eval/ }
  end
end
