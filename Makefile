prefix = /usr/local
exec_prefix = $(prefix)
sbindir = $(exec_prefix)/sbin
sysconfdir = /etc

INSTALL_DIR = $(DESTDIR)/var/app/puavo-web
CONF_DIR = $(DESTDIR)$(sysconfdir)/puavo-web
RAILS_CONFIG_DIR = $(INSTALL_DIR)/config
INSTALL = install
INSTALL_PROGRAM = $(INSTALL)

build:
	git rev-parse HEAD > GIT_COMMIT
	bundle install --deployment
	npm install --registry http://registry.npmjs.org # nib for stylys
	bundle exec rake puavo:configuration
	bundle exec rake assets:precompile
	bundle exec rake db:migrate
	RAILS_ENV=test bundle exec rake db:migrate
	$(MAKE) tags

update-gemfile-lock: clean
	rm -f Gemfile.lock
	bundle install

clean-for-install:
	# Remove testing gems
	bundle install --deployment --without test
	bundle clean

	# Remove any testing or development configuration files
	rm -f config/*.yml
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
		README.rdoc \
		script \
		vendor \
		.bundle \
		db \
		$(INSTALL_DIR)

	cp -r rest/lib $(INSTALL_DIR)/rest

	rm -f $(RAILS_CONFIG_DIR)/database.yml

	cp config/database.yml.development $(CONF_DIR)/database.yml
	ln -s ../../../../etc/puavo-web/database.yml $(RAILS_CONFIG_DIR)/database.yml

	cp config/services.yml.example $(CONF_DIR)/services.yml
	ln -s ../../../../etc/puavo-web/services.yml $(RAILS_CONFIG_DIR)/services.yml

	cp config/organisations.yml.development $(CONF_DIR)/organisations.yml
	ln -s ../../../../etc/puavo-web/organisations.yml $(RAILS_CONFIG_DIR)/organisations.yml

	cp config/ldap.yml.development $(CONF_DIR)/ldap.yml
	ln -s ../../../../etc/puavo-web/ldap.yml $(RAILS_CONFIG_DIR)/ldap.yml

	cp config/puavo_devices.yml.development $(CONF_DIR)/puavo_devices.yml
	ln -s ../../../../etc/puavo-web/puavo_devices.yml $(RAILS_CONFIG_DIR)/puavo_devices.yml

	cp config/unicorn.rb.example $(CONF_DIR)/unicorn.rb
	ln -s ../../../../etc/puavo-web/unicorn.rb $(RAILS_CONFIG_DIR)/unicorn.rb

	cp config/puavo_external_files.yml.example $(CONF_DIR)/puavo_external_files.yml
	ln -s ../../../../etc/puavo-web/puavo_external_files.yml $(RAILS_CONFIG_DIR)/puavo_external_files.yml

	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-external-service
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-web-prompt
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-owner

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
