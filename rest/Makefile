prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	git rev-parse HEAD > GIT_COMMIT
	cp ../VERSION VERSION
	bundle install --deployment

update-gemfile-lock: clean
	rm -f Gemfile.lock
	bundle install

clean-for-install:
	bundle install --deployment --without test shared
	bundle clean

clean:
	rm -rf .bundle vendor

install: clean-for-install
	# Delete .git dir and caches from vendor/. Caused some permission issues on
	# .deb builder
	find vendor/ -type d -name .git | xargs rm -rf
	rm -rf vendor/bundle/ruby/*/cache/bundler/git

	mkdir -p $(DESTDIR)$(installdir)
	mkdir -p $(DESTDIR)$(sysconfdir)
	mkdir -p $(DESTDIR)$(prefix)/bin
	cp -r \
		VERSION \
		GIT_COMMIT \
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
	bundle exec turn test/*_test.rb

serve-dev:
	bundle exec shotgun --host 0.0.0.0 --port 9393 --server puma

serve-production:
	RACK_ENV=production bundle exec rackup --host 0.0.0.0 --port 9393 --server puma

