class UserWorker
  include Sidekiq::Worker

  def perform
    logger.debug 'Doing hard work'
    sleep 30
    logger.debug 'DONE'
  end
end
