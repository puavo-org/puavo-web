build:
	bundle install --deployment

yard:
	bundle exec yard doc root.rb .

dev:
	bundle exec shotgun
