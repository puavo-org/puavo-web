# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_puavo-devices_session',
  :secret      => '1309e8fd59bc737aa4afc564da7582842dd122f33aa9336be6a63aa043ade55e87a05bf83aa987154d2752dfb6b13beda06eac19715da429fbbb23db09b765b9'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
