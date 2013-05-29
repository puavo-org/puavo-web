
all:
	bundle install --deployment --without development
	npm install # nib for stylys
	bundle exec rake assets:precompile
	## Activate when puavo-users package is being build too
	# $(MAKE) -C rest

install:
	@echo todo

test-spec:
	bundle exec rspec -b

test-rest:
	$(MAKE) -C rest test

test-acceptance:
	bundle exec cucumber features/registering_devices.feature
	bundle exec cucumber --exclude registering_devices

test: test-spec test-rest test-acceptance
