source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry"
gem "unicorn", "5.4.1"    # 5.5.0 has a bug and I don't want to use development versions
gem "fluent-logger"
gem "gibberish"
gem "http"
gem "json"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt", "2.1.0"
gem "sshkey"
gem "i18n-js"
gem "byebug"

gem "sassc-rails"
gem "jquery-rails"

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
