source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn"
gem "fluent-logger"
gem "gibberish"
gem "http"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt"
gem "sshkey"
gem "i18n-js"
gem "byebug"
gem "nib"

group :assets do
  gem "stylus"
  gem "jquery-rails"
end

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber"
  gem "cucumber-rails"
  gem "database_cleaner"
  gem "greenletters"
  gem "rbtrace"
  gem "rspec"
  gem "rspec-rails"
  gem "ruby-prof"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
end

