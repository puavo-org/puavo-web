prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	RACK_ENV=production bundle install --deployment --without rest_development
	$(MAKE) yard

yard:
	mkdir -p public/doc
	bundle exec yard doc --output-dir public/doc --exclude vendor root.rb .

update-production-gemfile.lock:
	sudo rm -rf .bundle Gemfile.lock
	# how to get rid of sudo...
	RACK_ENV=production sudo -E bundle install

install:
	mkdir -p $(DESTDIR)$(installdir)
	mkdir -p $(DESTDIR)$(sysconfdir)
	cp -r \
		*.rb \
		config.ru \
		Gemfile \
		Gemfile.lock \
		Makefile \
		resources \
		vendor \
		.bundle \
		$(DESTDIR)$(installdir)

install-client:
	mkdir -p $(DESTDIR)$(prefix)/sbin
	install -m 644 bin/puavo-post-ltsp-server-load $(DESTDIR)$(prefix)/sbin

.PHONY: test
test:
	bundle exec ruby1.9.1 test/all.rb

dev:
	bundle exec shotgun
