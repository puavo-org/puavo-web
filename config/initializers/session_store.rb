# Be sure to restart your server when you modify this file.

if ENV['RAILS_ENV'] == 'test'
  # Only works in the test environment
  Rails.application.config.session_store :cookie_store, key: '_puavo_users_session'
else
  # This works in development and production
  Rails.application.config.session_store :cookie_store, {
    :key => '_puavo_users_session',
    :same_site => :strict,
    :secure => :true,
  }
end
