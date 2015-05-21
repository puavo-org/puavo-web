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
	npm install --registry http://registry.npmjs.org # nib for stylys
	bundle exec rake assets:precompile
	$(MAKE) tags

update-gemfile-lock: clean
	rm -f Gemfile.lock
	GEM_HOME=.tmpgem bundle install
	rm -rf .tmpgem
	bundle install --deployment


clean-for-install:
	# Remove testing gems
	bundle install --deployment --without test
	bundle clean
	rm -f config/*.sqlite3

clean-assets:
	rm -rf public/assets
	rm -rf tmp/cache/assets

clean: clean-assets
	rm -rf .bundle
	rm -rf vendor/bundle
	rm -rf node_modules

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
		Gemfile.shared \
		lib \
		Makefile \
		monkeypatches.rb \
		package.json \
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
	cp $(RAILS_CONFIG_DIR)/services.yml.example $(CONF_DIR)/services.yml
	cp $(RAILS_CONFIG_DIR)/organisations.yml.development $(CONF_DIR)/organisations.yml
	cp $(RAILS_CONFIG_DIR)/ldap.yml.development $(CONF_DIR)/ldap.yml
	cp $(RAILS_CONFIG_DIR)/redis.yml.development $(CONF_DIR)/redis.yml
	cp $(RAILS_CONFIG_DIR)/puavo_web.yml.development $(CONF_DIR)/puavo_web.yml
	cp $(RAILS_CONFIG_DIR)/unicorn.rb.example $(CONF_DIR)/unicorn.rb
	cp $(RAILS_CONFIG_DIR)/puavo_external_files.yml.example $(CONF_DIR)/puavo_external_files.yml


	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-external-service
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-web-prompt
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-owner

symlink-config:
	ln -sf /etc/puavo-web/ldap.yml config/ldap.yml
	ln -sf /etc/puavo-web/organisations.yml config/organisations.yml
	ln -sf /etc/puavo-web/puavo_web.yml config/puavo_web.yml
	ln -sf /etc/puavo-web/puavo_external_files.yml config/puavo_external_files.yml
	ln -sf /etc/puavo-web/redis.yml config/redis.yml
	ln -sf /etc/puavo-web/secret_token.rb config/initializers/secret_token.rb
	ln -sf /etc/puavo-web/services.yml config/services.yml
	ln -sf /etc/puavo-web/unicorn.rb config/unicorn.rb

.PHONY: tags
tags:
	bundle exec ripper-tags -R --exclude=vendor --exclude rest

test-rest:
	$(MAKE) -C rest test

test-acceptance:
	bundle exec cucumber features/registering_devices.feature
	bundle exec cucumber --exclude registering_devices

.PHONY: test
test:
	bundle exec rspec --format documentation
	bundle exec cucumber --color --tags ~@start_test_server
	bundle exec cucumber --color --tags @start_test_server
	bundle exec rails runner acl/runner.rb

seed:
	bundle exec rails runner db/seeds.rb

server:
	bundle exec rails server

install-build-dep:
	mk-build-deps --install debian.default/control \
		--tool "apt-get --yes --force-yes" --remove

deb:
	rm -rf debian
	cp -a debian.default debian
	dpkg-buildpackage -us -uc
