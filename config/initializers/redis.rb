require "connection_pool"
require "redis"

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/1")

RedisPool = ConnectionPool.new(
  size: Integer(ENV.fetch("REDIS_POOL", 5)),
  timeout: 2
) do
  Redis.new(url: redis_url)
end
