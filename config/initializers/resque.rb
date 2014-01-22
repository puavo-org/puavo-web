Resque.redis = Redis::Namespace.new(:resque, :redis => REDIS_CONNECTION)
Resque.after_fork do |job|
  REDIS_CONNECTION = Redis.new YAML.load_file(REDIS_CONFIG).symbolize_keys
  Resque.redis = Redis::Namespace.new(:resque, :redis => REDIS_CONNECTION)
end
