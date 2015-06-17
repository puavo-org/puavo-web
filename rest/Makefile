prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	git rev-parse HEAD > GIT_COMMIT
	cp ../VERSION VERSION
	cp ../app/assets/images/anonymous.png resources/anonymous.png
	bundle install --deployment
	$(MAKE) tags

update-gemfile-lock: clean
	rm -f Gemfile.lock
	GEM_HOME=.tmpgem bundle install
	rm -rf .tmpgem
	bundle install --deployment

clean-for-install:
	bundle install --deployment --without test shared
	bundle clean

clean: clean-doc
	rm -rf .bundle vendor

.PHONY: tags
tags:
	bundle exec ripper-tags -R --exclude=vendor --exclude rest

install: clean-for-install
	# Delete .git dir and caches from vendor/. Caused some permission issues on
	# .deb builder
	find vendor/ -type d -name .git | xargs rm -rf
	rm -rf vendor/bundle/ruby/*/cache/bundler/git

	mkdir -p $(DESTDIR)$(installdir)
	mkdir -p $(DESTDIR)$(sysconfdir)
	mkdir -p $(DESTDIR)$(prefix)/bin
	mkdir -p $(DESTDIR)/etc/cron.hourly

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
	install -t $(DESTDIR)$(prefix)/bin bin/puavo-rest-scheduled-jobs
	ln -s ../../usr/bin/puavo-rest-scheduled-jobs $(DESTDIR)/etc/cron.hourly/puavo-rest-scheduled-jobs

install-client:
	mkdir -p $(DESTDIR)$(prefix)/sbin
	install -m 644 bin/puavo-load-reporter $(DESTDIR)$(prefix)/sbin

.PHONY: test
test:
	bundle exec ruby1.9.1 test/all.rb

server:
	bundle exec puma

server-dev:
	bundle exec shotgun --host 0.0.0.0 --port 9292 --server puma

.PHONY: doc
doc:
	bundle exec yard doc

clean-doc:
	rm -rf yarddocs/ .yardoc/

doc-publish: doc
	cp Makefile yarddocs
	$(MAKE) -C yarddocs _doc-publish

_doc-publish:
	git init
	git add -A
	git commit -m "deploy"
	git push git@github.com:opinsys/puavo-users.git master:gh-pages -f


doc-server: doc
	bundle exec yard server --reload

server-production:
	RACK_ENV=production bundle exec rackup --host 0.0.0.0 --port 9292 --server puma

