require 'base64'

class SearchSettings
  attr_accessor :terms
  attr_accessor :school_filter
  attr_accessor :is_regexp
  attr_accessor :is_reverse
  attr_accessor :remove_misses

  attr_accessor :users_type
  attr_accessor :users_locked
  attr_accessor :devices_types

  def initialize
    @terms = []
    @school_filter = '(puavoSchool=*)'
    @is_regexp = false
    @is_reverse = false
    @remove_misses = false

    @users_type = :all
    @users_locked = :ignore
    @devices_types = [:laptop, :fatclient, :printer, :others]
  end
end

class ExtendedSearchController < ApplicationController
  # GET /extended_search
  def index
    return if redirected_nonowner_user?

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

    if settings.terms.empty?
      return make_error(t('extended_search.controller.no_search_terms'))
    end

    # If school filtering is enabled, find out the target school's DN
    if params.include?(:schoolLimit) && !params[:schoolLimit].empty?
      begin
        s = School.find(params[:schoolLimit].to_i)
        settings.school_filter = "(puavoSchool=#{s.dn})"
      rescue StandardError => e
        puts "----> #{e}"
        return make_error(t('extended_search.controller.school_limit_failed'))
      end
    end

    if params.include?(:isRegexp) && params[:isRegexp]
      settings.is_regexp = true
    end

    if params.include?(:isReverse) && params[:isReverse]
      settings.is_reverse = true
    end

    if params.include?(:removeMisses) && params[:removeMisses]
      settings.remove_misses = true
    end

    if params.include?(:perTermSettings) && params[:perTermSettings]
      # parse per-term type settings
      pt = params[:perTermSettings]

      devices = pt.fetch(:devices, {})
      settings.devices_types = []
      settings.devices_types << :laptop if devices.fetch(:laptop, true)
      settings.devices_types << :fatclient if devices.fetch(:fatclient, true)
      settings.devices_types << :printer if devices.fetch(:printer, true)
      settings.devices_types << :other if devices.fetch(:other, true)

      users = pt.fetch(:users, {})
      settings.users_type = :marked_for_deletion if users.fetch(:type, 'all') == 'marked_for_deletion'
      settings.users_type = :normal if users.fetch(:type, 'all') == 'normal'
      settings.users_type = :all if users.fetch(:type, 'all') == 'all'

      settings.users_locked = :locked if users.fetch(:locked, 'ignore') == 'locked'
      settings.users_locked = :unlocked if users.fetch(:locked, 'ignore') == 'unlocked'
      settings.users_locked = :ignore if users.fetch(:locked, 'ignore') == 'ignore'
    end

    if settings.is_regexp
      # Make sure each search term is a valid regexp
      terms2 = []

      settings.terms.each do |t|
        begin
          terms2 << Regexp.new(t)
        rescue
          return make_error(t('extended_search.controller.invalid_regexp') + "\"#{t}\"")
        end
      end

      #settings.terms = terms2
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

        when 'device-current-image'
          search_device_current_image(settings)

        when 'device-mac'
          search_device_mac(settings)

        when 'device-tags'
          search_device_tags(settings)

        when 'device-monitors-xml'
          search_device_monitors_xml(settings)

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

  # Retrieves all users in the specified school
  def get_all_users(school_filter)
    # TODO: Don't include attributes that aren't needed in the current search.
    # For example, when searching for usernames, we can skip email addresses.
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

  # Converts a "puavo user" to something we can easily use when rendering a template
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
      :exact_removal_time => u.include?('puavoRemovalRequestTime') ? convert_timestamp(Time.strptime(u['puavoRemovalRequestTime'][0], '%Y%m%d%H%M%S%z')) : nil,
    }
  end

  def should_skip_user(user, settings)
    # Filter by deletion mark status
    if settings.users_type != :all
      is_marked_for_deletion = user.include?('puavoRemovalRequestTime')
      return true if settings.users_type == :marked_for_deletion && !is_marked_for_deletion
      return true if settings.users_type == :normal && is_marked_for_deletion
    end

    # Filter by locked status
    if settings.users_locked != :ignore
      if user.include?('puavoLocked') && user['puavoLocked'][0] == 'TRUE'
        is_locked = true
      else
        is_locked = false
      end

      return true if settings.users_locked == :locked && !is_locked
      return true if settings.users_locked == :unlocked && is_locked
    end

    # If we made it this far, then the user must not be skipped
    return false
  end

  # Iterates over all users and calls the user-supplied "matcher" block for every user and every
  # search term. If the matcher returns (true, string) then the "string" is added to search results
  # to indicate which part of the term was matched.
  def _do_user_search(settings, &matcher)
    all_users = get_all_users(settings.school_filter)
    @results = []
    @num_terms = settings.terms.count
    @num_hits = 0
    @num_misses = 0
    @total = 0
    @elapsed = Time.now

    settings.terms.each do |term|
      found = false

      all_users.each do |user|
        next if should_skip_user(user[1], settings)
        result, matched = matcher.call(user[1], term)

        if settings.is_reverse
          next if result
        else
          next unless result
        end

        # store a match
        @results << [term, matched, convert_user(user[1])]
        @total += 1
        found = true
      end

      @num_hits += 1 if found
      @num_misses += 1 unless found

      next if found

      # no hits for this term
      @results << [term, nil] unless settings.remove_misses
    end

    @elapsed = Time.now - @elapsed
    @elapsed = "<0.001" if @elapsed < 0.001

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
    @num_terms = settings.terms.count
    @num_hits = 0
    @num_misses = 0
    @total = 0
    @elapsed = Time.now

    # FIXME: This is too complicated to be implemented as a block, but it should not be.

    # Micro-optimization: pre-downcase all names, since we're doing
    # only case-insensitive comparisons
    all_users.each do |user|
      begin
        user[1]['down_sn'] = user[1]['sn'][0].downcase
        user[1]['down_givenName'] = user[1]['givenName'][0].downcase
      rescue
        # There are users out there who have only one name. They shouldn't exist, but they do.
        # Skip them.
      end
    end

    settings.terms.each do |term|
      found = false

      # How to interpret the name?
      comma = term.index(',')

      if comma && (comma > 0) && (comma < term.size)
        # First/last name separation is indicated with a comma
        first_name = term[0..comma-1].strip
        last_name = term[comma+1..-1].strip
      else
        # Use a regexp to split the name into parts and hope for the best
        parts = term.split(/[\s,']/)
        first_name = parts.first
        last_name = parts.last
      end

      # (lastname, firstname) instead of (firstname, lastname)
      if last_is_first
        first_name, last_name = last_name, first_name
      end

      # Always case-insensitive matches
      first_name.downcase!
      last_name.downcase!

      all_users.each do |user|
        next unless user[1]['down_givenName'] == first_name && user[1]['down_sn'] == last_name
        @results << [term, nil, convert_user(user[1])]
        @total += 1
        found = true
      end

      @num_hits += 1 if found
      @num_misses += 1 unless found

      next if found
      @results << [term, nil] unless settings.remove_misses
    end

    @elapsed = Time.now - @elapsed
    @elapsed = "<0.001" if @elapsed < 0.001

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
    @num_terms = settings.terms.count
    @num_hits = 0
    @num_misses = 0
    @total = 0
    @elapsed = Time.now

    settings.terms.each do |term|
      found = false

      all_groups.each do |group|
        result, matched = matcher.call(group[1], term)
        next unless result

        @results << [term, matched, convert_group(group[1])]
        @total += 1
        found = true
      end

      @num_hits += 1 if found
      @num_misses += 1 unless found

      next if found

      @results << [term, nil] unless settings.remove_misses
    end

    @elapsed = Time.now - @elapsed
    @elapsed = "<0.001" if @elapsed < 0.001

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
      'puavoDeviceCurrentImage',
      'puavoTag',
      'puavoDeviceKernelVersion',
      'puavoDeviceKernelArguments',
      'puavoDeviceMonitorsXML',
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

  def should_skip_device(device, settings)
    case device['puavoDeviceType'][0]
      when 'laptop'
        type = :laptop

      when 'fatclient'
        type = :fatclient

      when 'printer'
        type = :printer

      else
        type = :other
    end

    #puts "#{device['puavoHostname'][0]}: type=|#{device['puavoDeviceType'][0]}| conv=|#{type}| want=|#{settings.devices_types}| include=|#{settings.devices_types.include?(type)}|"
    return !settings.devices_types.include?(type)
  end

  def _do_device_search(settings, &matcher)
    all_devices = get_all_devices(settings.school_filter)
    @results = []
    @num_terms = settings.terms.count
    @num_hits = 0
    @num_misses = 0
    @total = 0
    @elapsed = Time.now

    settings.terms.each do |term|
      found = false

      all_devices.each do |device|
        next if should_skip_device(device[1], settings)
        result, matched = matcher.call(device[1], term)

        if settings.is_reverse
          next if result
        else
          next unless result
        end

        @results << [term, matched, convert_device(device[1])]
        @total += 1
        found = true
      end

      @num_hits += 1 if found
      @num_misses += 1 unless found

      next if found

      @results << [term, nil, nil] unless settings.remove_misses
    end

    @elapsed = Time.now - @elapsed
    @elapsed = "<0.001" if @elapsed < 0.001

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

  def search_device_current_image(settings)
    _do_device_search(settings) do |device, term|
      # Always a regexp search
      if device.include?('puavoDeviceCurrentImage')
        match_term(device['puavoDeviceCurrentImage'], term, true)
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

  def search_device_monitors_xml(settings)
    _do_device_search(settings) do |device, term|
      # Always a regexp search
      if device.include?('puavoDeviceMonitorsXML')
        match_term(device['puavoDeviceMonitorsXML'], term, true)
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
