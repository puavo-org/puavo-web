
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
	bundle exec cucumber

test: test-spec test-acceptance test-rest
