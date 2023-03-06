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

ESBUILD = node_modules/.bin/esbuild
# es2020 has all the features currently used in the system, so target it.
# --minify is not enabled by default, because source maps are broken (some
# componen (Sprockets?) insists they're in public/assets, which isn't true,
# but I can't find a way to change that).
ESBUILD_FLAGS = --bundle --charset=utf8 --target=es2020 #--minify #--sourcemap
JS_OUTPUT = app/assets/javascripts/bundles
JS_INPUT = \
	app/assets/javascripts/modal_popup.js \
	app/assets/javascripts/supertable3.js \
	app/assets/javascripts/puavoconf_editor.js \
	app/assets/javascripts/import_tool.js \
	app/assets/javascripts/puavomenu_editor.js

build: config-to-example
	git rev-parse HEAD > GIT_COMMIT
	bundle install --deployment
	npm ci --registry https://registry.npmjs.org
	find node_modules/\@esbuild/ -type f ! -regex "linux-x64" -delete
	$(MAKE) js
	bundle exec rake assets:precompile

update-gemfile-lock: clean js-clean
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
	rm -rf node_modules

js-clean:
	rm -rf app/assets/javascripts/bundles/*

js-server:
	$(ESBUILD) $(ESBUILD_FLAGS) --watch --outdir=$(JS_OUTPUT) $(JS_INPUT)

js:
	$(ESBUILD) $(ESBUILD_FLAGS) --minify --outdir=$(JS_OUTPUT) $(JS_INPUT)

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

install: clean-for-install mkdirs config-to-system
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
		package.json \
		node_modules \
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

	for conf_file in ldap.yml organisations.yml puavoconf_definitions.json \
			 puavo_external_files.yml puavo_web.yml redis.yml \
			 releases.json secrets.yml services.yml unicorn.rb; do \
	  cp $(RAILS_CONFIG_DIR)/$${conf_file}.example $(CONF_DIR)/$${conf_file}; \
	done

	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-external-service
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-web-prompt
	$(INSTALL_PROGRAM) -t $(DESTDIR)$(sbindir) script/puavo-add-owner

.PHONY: config-to-example
config-to-example:
	for conf_file in ldap.yml organisations.yml puavoconf_definitions.json \
			 puavo_external_files.yml puavo_web.yml redis.yml \
			 releases.json secrets.yml services.yml unicorn.rb; do \
	  ln -fns "$${conf_file}.example" "config/$${conf_file}"; \
	done

.PHONY: config-to-system
config-to-system:
	for conf_file in ldap.yml organisations.yml puavoconf_definitions.json \
			 puavo_external_files.yml puavo_web.yml redis.yml \
			 releases.json secrets.yml services.yml unicorn.rb; do \
	  ln -fns "/etc/puavo-web/$${conf_file}" "config/$${conf_file}"; \
	done

test-rest: config-to-system
	$(MAKE) -C rest test

test-acceptance:
	bundle exec cucumber features/registering_devices.feature
	bundle exec cucumber --exclude registering_devices

.PHONY: test
test: config-to-system
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

server: config-to-system
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
