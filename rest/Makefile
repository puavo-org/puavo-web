prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	RACK_ENV=production bundle install --deployment --without rest_development
	RACK_ENV=production $(MAKE) yard

yard:
	mkdir -p public/doc
	bundle exec yard doc --output-dir public/doc --exclude vendor root.rb .

update-production-gemfile.lock:
	sudo rm -rf .bundle Gemfile.lock
	# how to get rid of sudo...
	RACK_ENV=production sudo -E bundle install

dev-install:
	sudo rm -rf .bundle Gemfile.lock
	sudo -E bundle install --without rails
	sudo -E bundle install --without rails --deployment

install:
	# Delete .git dir and caches from vendor/. Caused some permission issues on
	# .deb builder
	find vendor/ -type d -name .git | xargs rm -rf
	rm -rf vendor/bundle/ruby/*/cache/bundler/git

	mkdir -p $(DESTDIR)$(installdir)
	mkdir -p $(DESTDIR)$(sysconfdir)
	mkdir -p $(DESTDIR)$(prefix)/bin
	cp -r \
		*.rb \
		lib \
		config.ru \
		Gemfile \
		Gemfile.lock \
		Makefile \
		resources \
		vendor \
		scripts \
		i18n \
		.bundle \
		views \
		public \
		middleware \
		doc \
		$(DESTDIR)$(installdir)
	
	install -t $(DESTDIR)$(prefix)/bin scripts/puavo-rest-prompt

install-client:
	mkdir -p $(DESTDIR)$(prefix)/sbin
	install -m 644 bin/puavo-load-reporter $(DESTDIR)$(prefix)/sbin

.PHONY: test
test:
	bundle exec ruby1.9.1 test/all.rb

serve-dev:
	bundle exec shotgun --host 0.0.0.0 --port 9393 --server puma

serve-production:
	RACK_ENV=production bundle exec rackup --host 0.0.0.0 --port 9393 --server puma


clean:
	rm -rf .bundle
	rm -rf vendor
	rm -rf public/doc/*
