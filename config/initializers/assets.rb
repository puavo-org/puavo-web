# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path
# Add Yarn node_modules folder to the asset load path.
#Rails.application.config.assets.paths << Rails.root.join('node_modules')

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
# Rails.application.config.assets.precompile += %w( admin.js admin.css )
Rails.application.config.assets.precompile += \
%w(
  search.js
  profile_editor.css
  password_forms.css
  password_validator.js
  puavoconf_editor.js
)

# SuperTable
Rails.application.config.assets.precompile += \
%w(
  supertable2.js
  filtereditor.js
  supertable2.fi.js
  supertable2.en.js
)

# The new import tool
Rails.application.config.assets.precompile += \
%w(
  new_import.js
  new_import.fi.js
  new_import.en.js
  csv_parser.js
  import_worker.js
)
