# Be sure to restart your server when you modify this file.

if ENV.include?('STRICT_SAMESITE_COOKIES')
  # Actual production mode, with HTTPS and everything
  Rails.application.config.session_store :cookie_store, {
    :key => '_puavo_users_session',
    :same_site => :strict,
    :secure => :true,
  }
else
  # Testing and development environments aren't exactly secure, but they don't have to be.
  # This is also used on puavo-standalone.
  Rails.application.config.session_store :cookie_store, {
    :key => '_puavo_users_session',
    :same_site => :lax,
  }
end
