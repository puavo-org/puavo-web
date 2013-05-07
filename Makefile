build:
	bundle install --deployment

yard:
	bundle exec yard doc root.rb .

publish-yard: yard
	git commit doc -m "Compiled YARD docs"
	git push origin master:gh-pages

.PHONY: test
test:
	bundle exec ruby1.9.1 test/*_test.rb

dev:
	bundle exec shotgun
