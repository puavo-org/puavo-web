module Puavo
  autoload :Organisation, 'puavo/organisation'
end

module PuavoOrganisation
  module Controllers
    autoload :Helpers, 'puavo_organisation/controllers/helpers'
  end
end

ActionController::Base.send :include, PuavoOrganisation::Controllers::Helpers
ActionController::Base.before_filter :set_organisation_to_session, :set_locale
ActionController::Base.helper_method :theme
