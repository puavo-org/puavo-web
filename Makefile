
all:
	# Install puavo-users gems without puavo-rest
	bundle install --deployment --without rest rest_development
	npm install # nib for stylys
	bundle exec rake assets:precompile
	# Install puavo-rest gems in to its own directory
	$(MAKE) -C rest

install:
	@echo todo

test-spec:
	bundle exec rspec -b

test-acceptance:
	bundle exec cucumber

test: test-spec test-acceptance
