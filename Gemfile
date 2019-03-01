source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn"
gem "fluent-logger"
gem "gibberish"
gem "http"
gem "json"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt"
gem "sshkey"
gem "i18n-js"
gem "byebug"

gem "sassc-rails"
gem "jquery-rails"

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber", "3.1.2"
  gem "cucumber-rails", "1.5.0"
  gem "greenletters"
  gem "rspec"
  gem "rspec-rails"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
end
