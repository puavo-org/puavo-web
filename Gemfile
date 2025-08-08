source 'http://rubygems.org'

# gems shared with puavo-rest
gem "rails", '7.0.8.7'
gem "sprockets"
gem "sqlite3"
gem "prawn"
gem "net-ldap"
gem "activeldap", :require => "active_ldap"
gem "rmagick"
gem "nokogiri"
gem 'concurrent-ruby', '1.3.4'    # 1.3.5 breaks every Rails below 7.1
gem 'sprockets-rails'

# puavo-web specific gems
gem "pry"
gem "unicorn"
gem "gibberish"
gem "http"
gem "json"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt"
gem "jwe"
gem "sshkey"
gem "i18n-js"
gem "byebug"
gem "gettext_i18n_rails"
gem "ttfunk"
gem "gettext"
gem "redis"
gem "redis-client"
gem "redis-namespace"
gem "jquery-rails"
gem "parse-cron"
gem 'webrick'               # Rails needs this but it isn't marked as a dependency?

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber"
  gem "cucumber-rails", "3.1.1", require: false     # don't install some ancient version from 2013
  gem "greenletters"
  gem "rspec"
  gem "rspec-rails"
  gem "timecop"
  gem "webmock"
end
