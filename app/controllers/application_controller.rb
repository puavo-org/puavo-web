# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include Puavo::AuthenticationHelper
  include Puavo::Helpers
  include Puavo::PuavomenuEditor    # temporary
  include FastGettext::Translation

  attr_reader :school
  helper_method( :theme, :current_user, :current_organisation,
                 :current_organisation?, :acquire_credentials,
                 :setup_authentication, :perform_login, :require_login,
                 :require_puavo_authorization,
                 :show_authentication_error, :store_location,
                 :redirect_back_or_default, :organisation_key_from_host,
                 :set_initial_locale, :remove_ldap_connection, :theme,
                 :school_list, :list_all_puavoconf_values, :rack_mount_point,
                 :password_management_host, :email_management_host,
                 :mfa_management_host )

  # Raise an exception if the CSRF check fails. Ignore JSON and XML
  # requests, as they're used in scripts and tests and protecting
  # those would be too arduous at the moment.
  protect_from_forgery with: :exception, prepend: true, unless: Proc.new { |c| c.request.format.json? || c.request.format.xml? }

  before_action do
    response.headers["X-puavo-web-version"] = "#{ PuavoUsers::VERSION } #{ PuavoUsers::GIT_COMMIT }"
  end

  # NOTICE: Don't do anything important in this method. The language is overridden later in
  # the require_login() method. This method exists, more or less, just to pacify the FastGettext
  # gem. If it's not called, the gem brings the server down.
  def set_gettext_language
    FastGettext.available_locales = ['en', 'fi', 'sv', 'de']  # 'en' must be first, otherwise tests can fail
    FastGettext.text_domain = 'puavoweb'
    FastGettext.add_text_domain('puavoweb', path: 'config/locales', type: :yaml)
    FastGettext.set_locale(params[:locale] || session[:locale] || request.env['HTTP_ACCEPT_LANGUAGE'])
    session[:locale] = I18n.locale = FastGettext.locale
  end

  before_action :set_gettext_language
  before_action :set_initial_locale
  before_action :setup_authentication
  before_action :require_login
  before_action :require_puavo_authorization
  before_action :find_school
  before_action :set_menu
  before_action :get_organisation

  before_action :is_pme_enabled

  after_action :remove_ldap_connection

  if ENV["RAILS_ENV"] == "production"
    rescue_from Exception do |error|
      @request = request
      @error = error
      @error_uuid = SecureRandom.uuid

      logger.error '-' * 50
      logger.error "UNHANDLED EXCEPTION (UUID #{@error_uuid})"
      logger.error "REQUEST URL: #{request.url}"
      logger.error "ERROR MESSAGE: #{@error.message}"
      logger.error "BACKTRACE:"
      logger.error @error.backtrace.join("\n")
      logger.error '-' * 50

      render status: 500, layout: false, template: 'errors/sorry'
    end
  end

  def send_404
    respond_to do |format|
      format.html { render status: 404, layout: false, template: 'errors/404' }
      format.all { render status: 404, text: '404 - not found' }
    end
  end

  # Cached schools query
  def school_list
    return @school_cache if @school_cache
    @school_cache = current_organisation.schools current_user
    @school_cache.sort{|a, b| a.displayName.downcase <=> b.displayName.downcase }
  end

  def list_all_puavoconf_values(org, school, device)
    # Parse and iterate over each "source" of puavo-conf data. Store them all, while keeping track
    # where they come from (organisation/school/device). All the views in various puavo-conf tables
    # can be constructed from these.
    full = {}

    [
      [org    ? JSON.parse(org)    : {}, 'org'],
      [school ? JSON.parse(school) : {}, 'sch'],
      [device ? JSON.parse(device) : {}, 'dev'],
    ].each do |config, source|
      config.each do |key, value|
        full[key] ||= {}
        full[key].merge!({ source => value })
      end
    end

    full.sort

    # There is no error handling here. If there's invalid puavo-conf somewhere in the chain, we must
    # explode loudly and violently with internal server error, to force someone to investigate it.
  end

  def rack_mount_point
    "/users"
  end

  def handle_date_multiparameter_attribute(object_params, attribute)
    year = object_params["#{attribute}(1i)"]
    month = object_params["#{attribute}(2i)"]
    day = object_params["#{attribute}(3i)"]

    if !year.nil? && !year.empty? && !month.nil? && !month.empty? && !day.nil? && !day.empty?
        object_params[attribute] = Time.local(year.to_i, month.to_i, day.to_i)
    end

  end

  # Fuzzy timestamps, used when listing users who are marked for later deletion
  def fuzzy_time(seconds)
    if seconds < 5.0
      return t('fuzzy_time.just_now')
    elsif seconds < 60.0
      return t('fuzzy_time.less_than_minute')
    elsif seconds < 3600.0
      m = (seconds / 60.0).to_i
      return (m == 1) ? t('fuzzy_time.minute') : t('fuzzy_time.minutes', :m => m)
    elsif seconds < 86400.0
      h = (seconds / 3600.0).to_i
      return (h == 1) ? t('fuzzy_time.hour') : t('fuzzy_time.hours', :h => h)
    else
      d = (seconds / 86400.0).to_i

      if d < 30
        return (d == 1) ? t('fuzzy_time.day') : t('fuzzy_time.days', :d => d)
      else
        month = (d / 30).to_i
        return (month == 1) ? t('fuzzy_time.month') : t('fuzzy_time.months', :month => month)
      end
    end
  end

  # Converts LDAP operational created/modified timestamps to localtime (server time)
  def convert_timestamp(t)
    t.localtime.strftime('%Y-%m-%d %H:%M:%S') rescue '?'
  end
  def convert_timestamp_pick_date(t)
    t.localtime.strftime('%Y-%m-%d') rescue '?'
  end

  def password_management_host
    url = "http://" +
      Puavo::CONFIG["password_management"]["host"]

    if Puavo::CONFIG["password_management"]["port"]
      url += ":" + Puavo::CONFIG["password_management"]["port"].to_s
    end

    return url
  end

  def email_management_host
    mgmt = Puavo::CONFIG['email_management']

    URI::HTTP.build(host: mgmt['host'], port: mgmt['port']).to_s
  end

  def mfa_management_host
    mgmt = Puavo::CONFIG['mfa_management']

    URI::HTTP.build(host: mgmt['host'], port: mgmt['port']).to_s
  end

  private

  def get_organisation
    begin
      @organisation_name = LdapOrganisation.current.cn
    rescue
      # This fails, for example, when opening password change forms, because
      # no LDAP connection exists when the form is opened. It's not a big
      # problem, though, because the password forms call a special method
      # named set_ldap_connection() which does more tricks to determine
      # the organisation name. That function also sets up @organisation_name,
      # so in the end, everything *should* work just fine...
      #puts "get_organisation() failed"
      logger.warn('get_organisation(): could not determine the current organisation, ' \
                  'assuming this is the password changing form')
      @organisation_name = nil
    end
  end

  def find_school
    if params.has_key?(:school_id)
      school_id = params[:school_id]
    elsif controller_name == 'schools' && params.has_key?(:id)
      school_id = params[:id]
    end

    unless school_id.nil?
      begin
        @school = School.find(school_id)
      rescue StandardError => e
        logger.error "Incorrect school id! Redirected..."
        flash[:alert] = t('flash.invalid_school_id')
        redirect_to schools_path
      end
    end
  end

  def set_menu
    # TODO: Where this should be required?
    # It must be require after all controllers are defined
    require "puavo_menu"

    @menu_items = PuavoMenu.new(self).children
    @child_items = []
    @menu_items.each do |i|
      @child_items = i.children if i.active?
    end

  end

  # Makes a list of schools and their admin users (DNs). The return value is formatted as follows:
  # {
  #   "school dn 1" => Set { ... },
  #   "school dn 2" => Set { ... }
  # }
  def list_school_admins
    School.search_as_utf8(attributes: ['puavoSchoolAdmin'])
          .collect { |s| [s[0], s[1].fetch('puavoSchoolAdmin', []).to_set] }
          .to_h.freeze
  end

  # Returns the current organisation owners in a (frozen) set
  def owners_set
    Array(LdapOrganisation.current.owner)
      .reject { |dn| dn == 'uid=admin,o=puavo' }
      .map(&:to_s)
      .to_set.freeze
  end

  # Returns true if the current user is an organisation owner
  def is_owner?
    current_user && Array(LdapOrganisation.current.owner).include?(current_user.dn)
  end

  # Returns true if a non-owner was redirected away from the page they were trying to view
  def redirected_nonowner_user?
    return false if current_user && Array(LdapOrganisation.current.owner).include?(current_user.dn)

    flash[:alert] = t('flash.you_must_be_an_owner')
    redirect_to schools_path
    return true
  end

  # Returns true if this user (username) is "super owner", ie. an owner user who has
  # been granted extra permissions. Usually these users are employees of the company
  # that makes Puavo.
  def super_owner?(name)
    begin
      super_owners = File.read("#{Rails.root}/config/super_owners.txt").split("\n")
    rescue StandardError => e
      logger.warn("ERROR: Can't query the super owner status: #{e}")
      super_owners = []
    end

    super_owners.include?(name)
  end

  def clean_image_name(hash)
    if hash.include?('puavoDeviceImage')
      hash['puavoDeviceImage'].strip!
      hash['puavoDeviceImage'] = hash['puavoDeviceImage'][0..-5] if hash['puavoDeviceImage'].end_with?('.img')
    end
  end

  def clear_puavoconf(hash)
    # Empty strings aren't valid JSON, so if there are no puavo-conf settings, we get
    # "{}" back from the edit form. Convert them into nil values, so the database
    # stays cleaner. Also strip out Windows linebreaks ("\r") that browsers like
    # to use instead of just "\n".
    if hash.include?('puavoConf')
      if hash['puavoConf'] == '{}'
        hash['puavoConf'] = ''
      else
        hash['puavoConf'].gsub!("\r", "")
      end
    end
  end

  # Loads the releases.json file if it exists. If it doesn't exist, then no problem.
  # It's 100% optional anyway. (Why reload it every time? Because it was meant to be
  # hot-replaceable on purpose.)
  def get_releases
    begin
      JSON.parse(File.read("#{Rails.root}/config/releases.json"))
    rescue
      {}
    end
  end

  def is_pme_enabled
    @pme_enabled = puavomenu_editing_enabled?
  end
end
