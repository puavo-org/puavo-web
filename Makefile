build:
	bundle install --deployment

yard:
	bundle exec yard doc root.rb .

publish-yard: yard
	git commit doc -m "Compiled YARD docs"
	git push origin master:gh-pages

dev:
	bundle exec shotgun
