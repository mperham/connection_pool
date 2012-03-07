# require an absolute path just in case this file is required when connection_pool is not in the $LOAD_PATH
require File.expand_path('../../connection_pool_basic_object', __FILE__)

class ConnectionPool < ConnectionPoolBasicObject
  VERSION = "0.1.0"
end
