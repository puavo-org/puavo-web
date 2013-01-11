# http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-1.3
class AuthorizationCode < ActiveRecord::Base
  LIFETIME = 2.minutes

  class Expired < UserError
  end

  def expired?
    age = Time.now - created_at
    age > LIFETIME
  end

  def consume
    if expired?
      destroy
      raise Expired
    end
    destroy
  end

end
