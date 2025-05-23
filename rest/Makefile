prefix = /usr/local
sysconfdir = /etc
installdir = /var/app/puavo-rest

build:
	git rev-parse HEAD > GIT_COMMIT
	cp ../VERSION VERSION
	mkdir -p public/images
	cp ../public/images/anonymous.png public/images/anonymous.png
	bundle config set --local deployment 'true'
	bundle install

update-gemfile-lock: clean
	rm -f Gemfile.lock
	GEM_HOME=.tmpgem bundle install
	rm -rf .tmpgem
	bundle config set --local deployment 'true'
	bundle install

clean: clean-doc
	rm -rf .bundle vendor

install:
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

.PHONY: test
test:
	# Run the enforced email tests separately
	bundle exec ruby test/enforced_email_addresses.rb
	bundle exec ruby test/all.rb

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
	touch .nojekyll
	git add -A
	git commit -m "deploy"
	git push git@github.com:puavo-org/puavo-web.git master:gh-pages -f


doc-server: doc
	bundle exec yard server --reload

server-production:
	RACK_ENV=production bundle exec rackup --host 0.0.0.0 --port 9292 --server puma

