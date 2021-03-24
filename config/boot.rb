# Set up gems listed in the Gemfile.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.

# The rails migration script wants to add this, but I don't see why we should use it.
# So what if it speeds up booting by 50%? By the time the server is rotated into
# production, it has been up for an hour or two. And during development, it doesn't
# really matter, shaving off a few seconds form something that happens once or twice
# in a hour does not matter. We don't even have this gem installed (it's part of
# new Rails apps).
#require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
