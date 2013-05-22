
all:
	bundle install --deployment --without rest
	npm install # nib for stylys
	bundle exec rake assets:precompile

install:
	@echo todo

test-spec:
	bundle exec rspec -b

test-acceptance:
	bundle exec cucumber

test: test-spec test-acceptance
