require 'base64'

class SearchSettings
  attr_accessor :terms
  attr_accessor :school_filter
  attr_accessor :is_regexp
  attr_accessor :remove_unmatched

  def initialize
    @terms = []
    @school_filter = '(puavoSchool=*)'
    @is_regexp = false
    @remove_unmatched = false
  end
end

class ExtendedSearchController < ApplicationController
  # GET /extended_search
  def index
    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # POST /extended_search
  def do_search
    #Access-Control-Allow-Origin: http://some.another.domain
    #Access-Control-Allow-Credentials: true

    # Extract and validate search parameters
    unless params.include?(:searchTerms) and params.include?(:searchTermsType)
      return make_error(t('extended_search.controller.invalid_search_data'))
    end

    settings = SearchSettings.new

    begin
      strings = params[:searchTerms].force_encoding('utf-8')
      settings.terms = strings.split("\n").map{ |t| t.strip }.reject{ |t| t.empty? || t[0] == '#' }
    rescue
      return make_error(t('extended_search.controller.search_terms_cleanup_failed'))
    end

    return make_error(t('extended_search.controller.no_search_terms')) if settings.terms.empty?

    # If school filtering is enabled, find out the target school's DN
    if params.include?(:schoolLimit) && !params[:schoolLimit].empty?
      begin
        s = School.find(params[:schoolLimit].to_i)
        settings.school_filter = "(puavoSchool=#{s.dn})"
      rescue StandardError => e
        puts {e}
      end
    end

    if params.include?(:isRegexp) && params[:isRegexp]
      settings.is_regexp = true
    end

    if params.include?(:removeUnmatched) && params[:removeUnmatched]
      settings.remove_unmatched = true
    end

    if settings.is_regexp
      # Make sure each search term is a valid regexp
      settings.terms.each do |t|
        begin
          Regexp.new(t)
        rescue
          return make_error(t('extended_search.controller.invalid_regexp') + "\"#{t}\"")
        end
      end
    end

    begin
      # Do a per-type search and send results back
      case params[:searchTermsType]

        # Users

        when 'user-puavoid'
          search_user_puavoid(settings)

        when 'user-uid'
          search_user_uid(settings)

        when 'user-name-lastfirst'
          search_user_name(settings, true)

        when 'user-name-firstlast'
          search_user_name(settings, false)

        when 'user-externalid'
          search_user_externalid(settings)

        when 'user-email'
          search_user_email(settings)

        when 'user-phone'
          search_user_phone(settings)

        # Groups

        when 'group-puavoid'
          search_group_puavoid(settings)

        when 'group-name'
          search_group_name(settings)

        when 'group-abbreviation'
          search_group_abbreviation(settings)

        when 'group-externalid'
          search_group_externalid(settings)

        # Devices

        when 'device-puavoid'
          search_device_puavoid(settings)

        when 'device-hostname'
          search_device_hostname(settings)

        when 'device-image'
          search_device_image(settings)

        when 'device-mac'
          search_device_mac(settings)

        when 'device-tags'
          search_device_tags(settings)

        when 'device-xrandr'
          search_device_xrandr(settings)

        when 'device-kernel-params'
          search_device_kernel_params(settings)

        when 'device-kernel-version'
          search_device_kernel_version(settings)

        when 'device-manufacturer'
          search_device_manufacturer(settings)

        when 'device-model'
          search_device_model(settings)

        when 'device-serial-number'
          search_device_serial_number(settings)

        # Error

        else
          return make_error(t('extended_search.controller.unknown_search_term_type') + "\"#{params[:searchTermsType]}\"")
      end
    rescue StandardError => e
      # Always return something, so the search button does not get stuck in disabled mode.
      # I don't know if this can leak something sensitive, but the source code is open,
      # so no secrets there.
      return make_error("Error: #{e}")
    end

  end

  private

  # ------------------------------------------------------------------------------------------------
  # UTILITY
  # ------------------------------------------------------------------------------------------------

  def make_error(message)
    render html: "<p class=\"searchError\">#{message}</p>".html_safe
  end

  SCHOOL_CACHE = {}

  def cache_school(school_dn)
    return SCHOOL_CACHE[school_dn] if SCHOOL_CACHE.include?(school_dn)

    begin
      s = School.find(school_dn)[0]
    rescue
      s = nil
    end

    SCHOOL_CACHE[school_dn] = s
    s
  end

  # I'm not proud of this method, but it works
  def match_term(haystack, needle, is_regexp)
    if haystack.class == Array
      # Assume it's an array of strings
      if is_regexp
        haystack.each { |h| return [true, h] if h.match(needle) }
        return [false, nil]
      else
        haystack.each { |h| return [true, h] if h == needle }
        return [false, nil]
      end
    else
      # Assume it's a string
      if is_regexp
        return [true, haystack] if haystack.match(needle)
      else
        return [haystack == needle, haystack]
      end
    end

    # We should never get here
    return [false, nil]
  end

  # ------------------------------------------------------------------------------------------------
  # USERS SEARCHING
  # ------------------------------------------------------------------------------------------------

  def get_all_users(school_filter)
    # TODO: Should this list be editable? We could search only for those
    # attributes different search term types actually need. I don't know
    # how much speed, if any, that would optimize.
    attributes = [
      'sn',
      'givenName',
      'uid',
      'puavoEduPersonAffiliation',
      'puavoId',
      'puavoSchool',
      'puavoDoNotDelete',
      'puavoRemovalRequestTime',
      'puavoLocked',
      'puavoExternalId',
      'mail',
      'telephoneNumber',
    ]

    User.search_as_utf8(:filter => school_filter, :attributes => attributes)
  end

  def convert_user(u)
    {
      :id => u['puavoId'][0],
      :name => [u['givenName'], u['sn']].join(' '),
      :uid => u['uid'][0],
      :affiliation => u['puavoEduPersonAffiliation'],
      :locked => u.include?('puavoLocked') && u['puavoLocked'][0] == "TRUE",
      :do_not_delete => u.include?('puavoDoNotDelete') && u['puavoDoNotDelete'][0] == "TRUE",
      :marked_for_deletion => u.include?('puavoRemovalRequestTime'),
      :school => cache_school(u['puavoSchool']),
      :exact_removal_time => nil,
    }
  end

  def _do_user_search(settings, &matcher)
    all_users = get_all_users(settings.school_filter)
    @results = []

    settings.terms.each do |term|
      found = false

      all_users.each do |user|
        result, matched = matcher.call(user[1], term)
        next unless result

        @results << [term, matched, convert_user(user[1])]
        found = true
      end

      next if found
      @results << [term, nil] unless settings.remove_unmatched
    end

    render partial: 'users'
  end

  def search_user_puavoid(settings)
    _do_user_search(settings) do |user, term|
      match_term(user['puavoId'][0], term, settings.is_regexp)
    end
  end

  def search_user_uid(settings)
    _do_user_search(settings) do |user, term|
      match_term(user['uid'][0], term, settings.is_regexp)
    end
  end

  def search_user_name(settings, last_is_first)
    all_users = get_all_users(settings.school_filter)
    @results = []

    # FIXME: This is too complicated to be implemented as a block, but it should not be.

    # Micro-optimization: pre-downcase all names, since we're doing
    # only case-insensitive comparisons
    all_users.each do |user|
      user[1]['down_sn'] = user[1]['sn'][0].downcase
      user[1]['down_givenName'] = user[1]['givenName'][0].downcase
    end

    settings.terms.each do |term|
      found = false

      t = term.split(/[\s,']/)
      t.reject!{|tt| tt.size == 0 }
      first_name = (last_is_first ? t[1] : t[0]).downcase
      last_name = (last_is_first ? t[0] : t[1]).downcase

      all_users.each do |user|
        next unless user[1]['down_givenName'] == first_name && user[1]['down_sn'] == last_name
        @results << [term, nil, convert_user(user[1])]
        found = true
      end

      next if found
      @results << [term, nil] unless settings.remove_unmatched
    end

    render partial: 'users'
  end

  def search_user_externalid(settings)
    _do_user_search(settings) do |user, term|
      if user.include?('puavoExternalId')
        match_term(user['puavoExternalId'][0], term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  def search_user_email(settings)
    _do_user_search(settings) do |user, term|
      if user.include?('mail')
        match_term(Array(user['mail']), term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  def search_user_phone(settings)
    _do_user_search(settings) do |user, term|
      if user.include?('telephoneNumber')
        match_term(Array(user['telephoneNumber']), term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  # ------------------------------------------------------------------------------------------------
  # GROUPS SEARCHING
  # ------------------------------------------------------------------------------------------------

  def get_all_groups(school_filter)
    attributes = [
      'puavoId',
      'cn',
      'displayName',
      'puavoEduGroupType',
      'puavoExternalId',
      'puavoSchool',
    ]

    Group.search_as_utf8(:filter => school_filter, :attributes => attributes)
  end

  def convert_group(g)
    {
      :id => g['puavoId'][0],
      :name => g['displayName'][0],
      :abbr => g['cn'][0],
      :type => g['puavoEduGroupType'],
      :eid => g['puavoExternalId'] || nil,
      :school => cache_school(g['puavoSchool']),
    }
  end

  def _do_group_search(settings, &matcher)
    all_groups = get_all_groups(settings.school_filter)
    @results = []

    settings.terms.each do |term|
      found = false

      all_groups.each do |group|
        result, matched = matcher.call(group[1], term)
        next unless result

        @results << [term, matched, convert_group(group[1])]
        found = true
      end

      next if found
      @results << [term, nil] unless settings.remove_unmatched
    end

    render partial: 'groups'
  end

  def search_group_puavoid(settings)
    _do_group_search(settings) do |group, term|
      match_term(group['puavoId'][0], term, settings.is_regexp)
    end
  end

  def search_group_name(settings)
    _do_group_search(settings) do |group, term|
      match_term(group['displayName'][0], term, settings.is_regexp)
    end
  end

  def search_group_abbreviation(settings)
    _do_group_search(settings) do |group, term|
      match_term(group['cn'][0], term, settings.is_regexp)
    end
  end

  def search_group_externalid(settings)
    _do_group_search(settings) do |group, term|
      if group.include?('puavoExternalId')
        match_term(group['puavoExternalId'][0], term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  # ------------------------------------------------------------------------------------------------
  # DEVICES SEARCHING
  # ------------------------------------------------------------------------------------------------

  def get_all_devices(school_filter)
    attributes = [
      'puavoId',
      'puavoHostname',
      'puavoDeviceType',
      'macAddress',
      'puavoSchool',
      'puavoDeviceManufacturer',
      'puavoDeviceModel',
      'serialNumber',
      'puavoDeviceImage',
      'puavoTag',
      'puavoDeviceKernelVersion',
      'puavoDeviceKernelArguments',
      'puavoDeviceXrandr',
    ]

    Device.search_as_utf8(:filter => school_filter, :attributes => attributes)
  end

  def convert_device(d)
    {
      :id => d['puavoId'][0],
      :name => d['puavoHostname'][0],
      :type => d['puavoDeviceType'][0],
      :school => cache_school(d['puavoSchool']),
    }
  end

  def _do_device_search(settings, &matcher)
    all_devices = get_all_devices(settings.school_filter)
    @results = []

    settings.terms.each do |term|
      found = false

      all_devices.each do |device|
        result, matched = matcher.call(device[1], term)
        next unless result

        @results << [term, matched, convert_device(device[1])]
        found = true
      end

      next if found
      @results << [term, nil, nil] unless settings.remove_unmatched
    end

    render partial: 'devices'
  end

  def search_device_puavoid(settings)
    _do_device_search(settings) do |device, term|
      match_term(device['puavoId'][0], term, settings.is_regexp)
    end
  end

  def search_device_hostname(settings)
    _do_device_search(settings) do |device, term|
      match_term(device['puavoHostname'][0], term, settings.is_regexp)
    end
  end

  def search_device_image(settings)
    _do_device_search(settings) do |device, term|
      # Always a regexp search
      if device.include?('puavoDeviceImage')
        match_term(device['puavoDeviceImage'], term, true)
      else
        [false, nil]
      end
    end
  end

  def search_device_mac(settings)
    _do_device_search(settings) do |device, term|
      if device.include?('macAddress')
        match_term(Array(device['macAddress']), term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  def search_device_tags(settings)
    _do_device_search(settings) do |device, term|
      if device.include?('puavoTag')
        match_term(device['puavoTag'], term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  def search_device_xrandr(settings)
    _do_device_search(settings) do |device, term|
      # Always a regexp search
      if device.include?('puavoDeviceXrandr')
        match_term(device['puavoDeviceXrandr'], term, true)
      else
        [false, nil]
      end
    end
  end

  def search_device_kernel_params(settings)
    _do_device_search(settings) do |device, term|
      # Always a regexp search
      if device.include?('puavoDeviceKernelArguments')
        match_term(device['puavoDeviceKernelArguments'], term, true)
      else
        [false, nil]
      end
    end
  end

  def search_device_kernel_version(settings)
    _do_device_search(settings) do |device, term|
      # Always a regexp search
      if device.include?('puavoDeviceKernelVersion')
        match_term(device['puavoDeviceKernelVersion'], term, true)
      else
        [false, nil]
      end
    end
  end

  def search_device_manufacturer(settings)
    _do_device_search(settings) do |device, term|
      if device.include?('puavoDeviceManufacturer')
        match_term(device['puavoDeviceManufacturer'][0], term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  def search_device_model(settings)
    _do_device_search(settings) do |device, term|
      if device.include?('puavoDeviceModel')
        match_term(device['puavoDeviceModel'][0], term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

  def search_device_serial_number(settings)
    _do_device_search(settings) do |device, term|
      if device.include?('serialNumber')
        match_term(device['serialNumber'][0], term, settings.is_regexp)
      else
        [false, nil]
      end
    end
  end

end
