# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_kilohaili_session',
  :secret      => '57fd0fc97fd03b46e42cc7de38ff572a79ca946b08eb4a2606d1b21496bb5d016eeaf4b18691c40312a3cda13c1c9e1f940c00a0e8adc0cafde79f428ebbdf54'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
