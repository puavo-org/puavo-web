source 'http://rubygems.org'

File.open("./Gemfile.shared") do |f|
  eval f.read, nil, "./Gemfile.shared"
end

gem "pry", "~> 0.10.1"
gem "unicorn", "~> 4.8.3"
gem "fluent-logger", "~> 0.4.3"
gem "gibberish", "~> 1.4.0"
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
  gem "rspec", "~> 2.14.1"
  gem "rspec-rails"
  gem "ruby-prof"
  gem "timecop"
  gem "ripper-tags"
  gem "webmock"
end

