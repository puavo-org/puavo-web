source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn"
gem "gibberish"
gem "http"
gem "json"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt", "2.1.0"
gem "sshkey"
gem "i18n-js"
gem "byebug", "11.0.1"    # Ruby 2.3.x

# last versions that work with Ruby 2.3.x
gem "ttfunk", "1.5.1"
gem "gettext", "3.2.9"
gem "redis-namespace", "1.6.0"

gem "sassc-rails"
gem "jquery-rails"

gem "parse-cron"

group :test do
  gem "capybara", "3.15.0"    # 3.15.0 is the last that works with Ruby 2.3.x
  gem "colorize"
  gem "cucumber"
  gem "cucumber-rails"
  gem "greenletters"
  gem "rspec"
  gem "rspec-rails"
  gem "timecop"
  gem "webmock"
end
