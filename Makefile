export PATH := node_modules/.bin:$(PATH)
prefix = /usr/local
exec_prefix = $(prefix)
sbindir = $(exec_prefix)/sbin
sysconfdir = /etc

INSTALL_DIR = $(DESTDIR)/var/app/puavo-web
CONF_DIR = $(DESTDIR)$(sysconfdir)/puavo-web
RAILS_CONFIG_DIR = $(INSTALL_DIR)/config
INSTALL = install
INSTALL_PROGRAM = $(INSTALL)

build: symlink-config
	git rev-parse HEAD > GIT_COMMIT
	bundle install --deployment
	bundle exec rake assets:precompile

update-gemfile-lock: clean
	rm -f Gemfile.lock
	GEM_HOME=.tmpgem bundle install
	rm -rf .tmpgem
	bundle install --deployment

clean-for-install:
	# Remove testing gems
	rm -f config/*.sqlite3

clean-assets:
	rm -rf public/assets
	rm -rf tmp/cache/assets

clean: clean-assets
	rm -rf .bundle
	rm -rf vendor/bundle

clean-deb:
	rm -f ../puavo-*.tar.gz ../puavo-*.deb ../puavo-*.dsc ../puavo-*.changes

mkdirs:
	mkdir -p $(CONF_DIR)
	mkdir -p $(RAILS_CONFIG_DIR)
	mkdir -p $(INSTALL_DIR)/tmp
	mkdir -p $(INSTALL_DIR)/db
	mkdir -p $(INSTALL_DIR)/log
	mkdir -p $(INSTALL_DIR)/rest
	mkdir -p $(DESTDIR)$(sbindir)

install: clean-for-install mkdirs
	cp -r \
		VERSION \
		GIT_COMMIT \
		app \
		config \
		config.ru \
		doc \
		Gemfile \
		Gemfile.lock \
		Makefile \
		monkeypatches.rb \
		public \
		Rakefile \
		README.md \
		script \
		vendor \
		.bundle \
		db \
		$(INSTALL_DIR)

	cp -r rest/lib $(INSTALL_DIR)/rest
	cp -r rest/resources $(INSTALL_DIR)/rest
	cp -r rest/views $(INSTALL_DIR)/rest
	cp -r rest/public $(INSTALL_DIR)/rest
	cp $(RAILS_CONFIG_DIR)/secrets.yml.example $(CONF_DIR)/secrets.yml
	cp $(RAILS_CONFIG_DIR)/services.yml.example $(CONF_DIR)/services.yml
	cp $(RAILS_CONFIG_DIR)/organisations.yml.development $(CONF_DIR)/organisations.yml
	cp $(RAILS_CONFIG_DIR)/ldap.yml.development $(CONF_DIR)/ldap.yml
	cp $(RAILS_CONFIG_DIR)/redis.yml.development $(CONF_DIR)/redis.yml
	cp $(RAILS_CONFIG_DIR)/puavo_web.yml.development $(CONF_DIR)/puavo_web.yml
	cp $(RAILS_CONFIG_DIR)/unicorn.rb.example $(CONF_DIR)/unicorn.rb
	cp $(RAILS_CONFIG_DIR)/puavo_external_files.yml.example $(CONF_DIR)/puavo_external_files.yml
	cp $(RAILS_CONFIG_DIR)/releases.json.example $(CONF_DIR)/releases.json
	cp $(RAILS_CONFIG_DIR)/puavoconf_definitions.json.example $(CONF_DIR)/puavoconf_definitions.json

	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-external-service
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-web-prompt
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-owner

symlink-config:
	ln -sf /etc/puavo-web/ldap.yml config/ldap.yml
	ln -sf /etc/puavo-web/organisations.yml config/organisations.yml
	ln -sf /etc/puavo-web/puavo_web.yml config/puavo_web.yml
	ln -sf /etc/puavo-web/puavo_external_files.yml config/puavo_external_files.yml
	ln -sf /etc/puavo-web/redis.yml config/redis.yml
	ln -sf /etc/puavo-web/secrets.yml config/secrets.yml
	ln -sf /etc/puavo-web/services.yml config/services.yml
	ln -sf /etc/puavo-web/unicorn.rb config/unicorn.rb
	ln -sf /etc/puavo-web/releases.json config/releases.json
	ln -sf /etc/puavo-web/puavoconf_definitions.json config/puavoconf_definitions.json

test-rest:
	$(MAKE) -C rest test

test-acceptance:
	bundle exec cucumber features/registering_devices.feature
	bundle exec cucumber --exclude registering_devices

.PHONY: test
test:
	bundle exec rspec --format documentation
	bundle exec rails runner acl/runner.rb
	AUTOMATIC_EMAIL_ADDRESSES=enabled bundle exec cucumber --color --tags @automatic_email \
			features/enforced_email_addresses.feature --format=message \
			--out log/cucumber-tests-automatic-email-addresses.json
	bundle exec cucumber --color --tags @start_test_server \
		--format=message --out log/cucumber-tests-TS.json
	bundle exec cucumber --color --tags "not @start_test_server" --tags "not @automatic_email" \
		--format=message --out log/cucumber-tests-notTS.json

seed:
	bundle exec rails runner db/seeds.rb

server:
	bundle exec rails server -b 0.0.0.0 -p 8081

.PHONY: deb
deb:
	cp -p debian/changelog.vc debian/changelog 2>/dev/null \
	  || cp -p debian/changelog debian/changelog.vc
	dch --newversion \
	    "$$(cat VERSION)+build$$(date +%s)+$$(git rev-parse HEAD)" \
	    "Built from $$(git rev-parse HEAD)"
	dch --release ''
	dpkg-buildpackage -us -uc
	cp -p debian/changelog.vc debian/changelog

.PHONY: install-build-deps
install-build-deps:
	mk-build-deps --install --tool 'apt-get --yes' --remove debian/control

.PHONY: upload-debs
upload-debs:
	dput puavo ../puavo-users_*.changes
