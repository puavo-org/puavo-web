prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	bundle install --deployment --without development

yard:
	bundle exec yard doc --exclude vendor root.rb .

publish-yard: yard
	git commit doc -m "Compiled YARD docs"
	git push origin master:gh-pages

install:
	mkdir -p $(DESTDIR)$(installdir)
	mkdir -p $(DESTDIR)$(sysconfdir)
	cp -r \
		config.ru \
		errors.rb \
		credentials.rb \
		root.rb \
		Gemfile \
		Gemfile.lock \
		Makefile \
		resources \
		vendor \
		.bundle \
		$(DESTDIR)$(installdir)

.PHONY: test
test:
	bundle exec ruby1.9.1 test/*_test.rb

dev:
	bundle exec shotgun
