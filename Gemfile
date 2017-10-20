source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry", "0.11.2"
gem "unicorn"
gem "fluent-logger"
gem "gibberish", "2.1.0"
gem "http"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt", "1.5.6"
gem "sshkey"
gem "i18n-js"
gem "byebug"
gem "nib"

#group :assets do
  gem "stylus"
  gem "jquery-rails"
#end

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber", "2.4.0"
  gem "cucumber-rails", "1.5.0"
  gem "greenletters"
  gem "rspec"
  gem "rspec-rails", "3.7.1"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
end
