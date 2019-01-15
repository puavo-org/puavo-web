source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn", "5.4.0"
gem "fluent-logger"
gem "gibberish", "2.1.0"
gem "http", "3.0.0"
gem "json", "2.1.0"
gem "sinatra-support", "1.2.2", :require => "sinatra/support"
gem "jwt", "2.1.0"
gem "sshkey", "1.9.0"
gem "i18n-js", "3.0.3"
gem "byebug"

gem "sassc-rails"
gem "jquery-rails",  "4.3.1"

group :test do
  gem "capybara"
  gem "colorize"
  gem "cucumber", "3.1.0"
  gem "cucumber-rails", "1.5.0"
  gem "greenletters", "0.3.0"
  gem "rspec"
  gem "rspec-rails"
  gem "timecop", "0.9.1"
  gem "ripper-tags", "0.5.0"
  gem "webmock", "3.2.1"
end
