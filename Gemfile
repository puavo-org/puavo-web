source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry", "~> 0.10.1"
gem "unicorn", "~> 4.8.3"
gem "debugger", "~> 1.6.8"
gem "fluent-logger", "~> 0.4.3"
gem "gibberish", "~> 1.4.0"
gem "http"
gem "sinatra-support", :require => "sinatra/support"
gem "jwt", "~> 0.1.8"
gem "sshkey", "~> 1.6.1"
gem "i18n-js", ">= 3.0.0.rc11"

group :assets do
  gem "stylus", "~> 0.7.2"
  gem "jquery-rails"
end

group :test do
  gem "capybara", "~> 2.4.4"
  gem "colorize"
  gem "cucumber", "~> 1.3.19"
  gem "cucumber-rails", "~> 1.4.2"
  gem "database_cleaner"
  gem "greenletters"
  gem "rbtrace"
  gem "rspec", "~> 2.14.1"
  gem "rspec-rails"
  gem "ruby-prof"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
end

