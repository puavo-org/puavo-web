prefix = /usr/local
sysconfdir = /etc
INSTALL_DIR = $(DESTDIR)/var/app/puavo-web
CONF_DIR = $(DESTDIR)$(sysconfdir)/puavo-web
RAILS_CONFIG_DIR = $(INSTALL_DIR)/config


build:
ifeq ($(wildcard config/database.yml),)
	cp config/database.yml.example config/database.yml
endif
	bundle install --deployment --without test
	npm install # nib for stylys
	bundle exec rake assets:precompile

mkdirs:
	mkdir -p $(CONF_DIR)
	mkdir -p $(RAILS_CONFIG_DIR)
	mkdir -p $(INSTALL_DIR)/tmp
	mkdir -p $(INSTALL_DIR)/db
	mkdir -p $(INSTALL_DIR)/log

install: mkdirs
	cp -r \
		app \
		config \
		config.ru \
		doc \
		Gemfile \
		Gemfile.lock \
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

	rm $(RAILS_CONFIG_DIR)/database.yml

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

	cp config/puavo_external_files.yml.development $(CONF_DIR)/puavo_external_files.yml
	ln -s ../../../../etc/puavo-web/puavo_external_files.yml $(RAILS_CONFIG_DIR)/puavo_external_files.yml

clean-assets:
	rm -rf public/assets
	rm -rf tmp/cache/assets

clean: clean-assets
	rm -rf .bundle
	rm -rf vendor/bundle
	rm -rf node_modules

test-spec:
	bundle exec rspec -b

test-rest:
	$(MAKE) -C rest test

test-acceptance:
	bundle exec cucumber features/registering_devices.feature
	bundle exec cucumber --exclude registering_devices

test: test-spec test-rest test-acceptance
