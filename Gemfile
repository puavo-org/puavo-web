source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn"
gem "debugger"
gem "fluent-logger", "~> 0.4.3"
gem "gibberish"
gem "http"
gem "sinatra-support", require: "sinatra/support"


group :assets do
  gem "stylus", "~> 0.7.2"
  gem "jquery-rails"
end

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber"
  gem "cucumber-rails"
  gem "cucumber-rails"
  gem "database_cleaner"
  gem "debugger"
  gem "greenletters"
  gem "rbtrace"
  gem "rspec", "~> 2.14.1"
  gem "rspec-rails"
  gem "ruby-prof"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
  gem "jwt", "~> 0.1.8"
end

