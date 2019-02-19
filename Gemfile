source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn"
gem "fluent-logger"
gem "gibberish"
gem "http", "3.0.0"
gem "json", "2.1.0"
gem "sinatra-support", "1.2.2", :require => "sinatra/support"
gem "jwt", "2.1.0"
gem "sshkey"
gem "i18n-js"
gem "byebug"

gem "sassc-rails"
gem "jquery-rails",  "4.3.1"

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber", "3.1.0"
  gem "cucumber-rails", "1.5.0"
  gem "greenletters"
  gem "rspec"
  gem "rspec-rails"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
end
