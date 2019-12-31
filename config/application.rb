require_relative 'boot'

require 'puavo'

# The Rails upgrade process wants this, but we cannot use it. We aren't using Rails'
# database layer and we don't have config/database.yml. I guess I could add an empty
# file, but I don't know enough of how Rails works to ensure that won't break anything.
#require 'rails/all'

require "action_controller/railtie"
require "action_mailer/railtie"
require "rails/test_unit/railtie"
require "sprockets/railtie"

require "active_ldap/railtie"

require_relative "../monkeypatches"
require_relative "./version"
require_relative "../rest/lib/external_login"

# Another line "rails app:update" wants that... just fails.
#Bundler.require(*Rails.groups)

if defined?(Bundler)
  # If you precompile assets before deploying to production, use this line
  Bundler.require(*Rails.groups(:assets => %w(development test)))
  # If you want your assets lazily compiled in production, use this line
  # Bundler.require(:default, :assets, Rails.env)
  Bundler.require(:shared)
end

module PuavoUsers
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.1

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Custom directories with classes and modules you want to be autoloadable.
    # config.autoload_paths += %W(#{config.root}/extras)
    config.autoload_paths += %W(#{config.root}/lib)

    # Only load the plugins named here, in the order given (default is alphabetical).
    # :all can be used as a placeholder for all plugins not explicitly named.
    # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

    config.exceptions_app = self.routes

    # Use memory cache
    config.cache_store = :memory_store

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Configure the default encoding used in templates for Ruby 1.9.
    config.encoding = "utf-8"

    # Configure sensitive parameters which will be filtered from the log file.
    config.filter_parameters += [
      :password,
      :new_password,
      :new_password_confirmation
    ]

    # Enable escaping HTML in JSON.
    config.active_support.escape_html_entities_in_json = true

    config.assets.precompile += ["font/fontello-puavo/css/puavo-icons.css", "devices/index.js"]

    #I18n.enforce_available_locales = false
    I18n.config.available_locales = [:en, :fi, :sv, :de]
    config.i18n.default_locale = :en

    # Enable deflate/gzip compression
    config.middleware.use Rack::Deflater
  end
end
