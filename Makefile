prefix = /usr/local
exec_prefix = $(prefix)
sbindir = $(exec_prefix)/sbin
sysconfdir = /etc

INSTALL_DIR = $(DESTDIR)/var/app/puavo-web
CONF_DIR = $(DESTDIR)$(sysconfdir)/puavo-web
RAILS_CONFIG_DIR = $(INSTALL_DIR)/config
INSTALL = install
INSTALL_PROGRAM = $(INSTALL)

build: worker-keys
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

worker-keys:
	openssl genrsa -out config/resque_worker_private_key 2048
	openssl rsa -in config/resque_worker_private_key -pubout > config/resque_worker_public_key

clean-for-install:
	# Remove testing gems
	bundle install --deployment --without test
	bundle clean
	# Do not put development keys in to the package
	rm -f config/initializers/secret_token.rb
	rm -f config/resque_worker_private_key
	rm -f config/resque_worker_public_key

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

	cp config/redis.yml.development $(CONF_DIR)/redis.yml
	ln -s ../../../../etc/puavo-web/redis.yml $(RAILS_CONFIG_DIR)/redis.yml

	cp config/puavo_devices.yml.development $(CONF_DIR)/puavo_devices.yml
	ln -s ../../../../etc/puavo-web/puavo_devices.yml $(RAILS_CONFIG_DIR)/puavo_devices.yml

	cp config/unicorn.rb.example $(CONF_DIR)/unicorn.rb
	ln -s ../../../../etc/puavo-web/unicorn.rb $(RAILS_CONFIG_DIR)/unicorn.rb

	cp config/puavo_external_files.yml.example $(CONF_DIR)/puavo_external_files.yml
	ln -s ../../../../etc/puavo-web/puavo_external_files.yml $(RAILS_CONFIG_DIR)/puavo_external_files.yml

	cp config/initializers/secret_token.rb.development $(CONF_DIR)/secret_token.rb
	ln -s ../../../../etc/puavo-web/secret_token.rb $(RAILS_CONFIG_DIR)/initializers/secret_token.rb

	cp config/resque_worker_private_key.development $(CONF_DIR)/resque_worker_private_key
	ln -s ../../../../etc/puavo-web/resque_worker_private_key $(RAILS_CONFIG_DIR)/resque_worker_private_key

	cp config/resque_worker_public_key.development $(CONF_DIR)/resque_worker_public_key
	ln -s ../../../../etc/puavo-web/resque_worker_public_key $(RAILS_CONFIG_DIR)/resque_worker_public_key

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
