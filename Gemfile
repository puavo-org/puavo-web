source 'http://rubygems.org'

# gems shared with puavo-rest
gem "rails", "5.2.4.5"
gem "sprockets", "3.7.2"    # I'm not going to deal with the manifest.js mess in sprockets 4.x anytime soon
gem "sqlite3"
gem "prawn"
gem "net-ldap"
gem "activeldap", "5.2.2", :require => "active_ldap"    # TODO: figure out why later versions fail
gem "rmagick"
gem "uuid"
gem "nokogiri"

# puavo-web specific games
gem "pry"
gem "unicorn"
gem "gibberish"
gem "http"
gem "json"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt"
gem "sshkey"
gem "i18n-js"
gem "byebug"
gem "gettext_i18n_rails"
gem "ttfunk"
gem "gettext"
gem "redis-namespace"
gem "sassc-rails"
gem "jquery-rails"
gem "parse-cron"

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber", "5.3.0"   # cucumber-rails is not compatible with cucumber 6
  gem "cucumber-rails"
  gem "greenletters"
  gem "rspec"
  gem "rspec-rails"
  gem "timecop"
  gem "webmock"
end
