prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	RACK_ENV=production bundle install --deployment --without rest_development

yard:
	bundle exec yard doc --exclude vendor root.rb .

update-production-gemfile.lock:
	sudo rm -rf .bundle Gemfile.lock
	# how to get rid of sudo...
	RACK_ENV=production sudo -E bundle install

publish-yard: yard
	git add doc
	git commit -m "Compiled YARD docs"
	git push -f origin master:gh-pages

install:
	mkdir -p $(DESTDIR)$(installdir)
	mkdir -p $(DESTDIR)$(sysconfdir)
	cp -r \
		*.rb \
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
