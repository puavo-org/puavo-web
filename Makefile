
all:
	bundle install --deployment
	bundle exec rake assets:precompile

install:
	@echo todo
