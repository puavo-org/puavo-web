# Be sure to restart your server when you modify this file.

if ENV['RAILS_ENV'] == 'test' || ENV['RAILS_ENV'] == 'development'
  # Testing and development environments aren't exactly secure, but they don't have to be
  Rails.application.config.session_store :cookie_store, {
    :key => '_puavo_users_session',
    :same_site => :lax,
  }
else
  # Production only, with SSL and everything
  Rails.application.config.session_store :cookie_store, {
    :key => '_puavo_users_session',
    :same_site => :strict,
    :secure => :true,
  }
end
