build:
	bundle install --deployment

yard:
	bundle exec yard doc root.rb .

publish-yard: yard
	git push orgin master:gh-pages

dev:
	bundle exec shotgun
