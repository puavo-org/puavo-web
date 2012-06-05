# http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-1.3
class AuthorizationCode < ActiveRecord::Base
  LIFETIME = 2.minutes

  def expired?
    age = Time.now - created_at
    age > LIFETIME
  end

end
