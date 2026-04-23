# frozen_string_literal: true

require 'set'

module DevicesHelper
  include Puavo::Helpers

  def classes(device)
    classes = Device.allowed_classes

    classes.map do |r|
      "<div>" +
        "<label>" +
        "<input " +
        ( device.classes.include?(r) ? 'checked="checked"' : "" ) +
        "id='devices_#{r}' name='device[classes][]' type='checkbox' value='#{r}' />#{r}" +
        "</label>" +
        "</div>\n"
    end
  end

  def title(device)
    case true
    when device.classes.include?('puavoNetbootDevice')
      t('shared.terminal_title')
    when device.classes.include?('puavoPrinter')
      t('shared.printer_title')
    when device.classes.include?('puavoServer')
      t('shared.server_title')
    else
      t('shared.title')
    end
  end

  def model_name_from_ppd(ppd)
    return I18n.t('helpers.ppd_file.no_file') if ppd.nil?
    if match_data = ppd.match(/\*ModelName:(.*)\n/)
      return match_data[1].lstrip.gsub("\"", "")
    end
    return I18n.t('helpers.ppd_file.cannot_detect_filetype')
  end

  def self.get_device_attributes()
    return [
      'puavoId',
      'puavoHostname',
      'puavoDisplayName',
      'puavoDeviceType',
      'puavoDeviceImage',
      'puavoDeviceCurrentImage',
      'macAddress',
      'serialNumber',
      'puavoDeviceManufacturer',
      'puavoDeviceModel',
      'puavoDeviceKernelArguments',
      'puavoDeviceKernelVersion',
      'puavoDeviceMonitorsXML',
      'puavoDeviceXrandr',
      'puavoTag',
      'puavoConf',
      'description',
      'puavoNotes',
      'puavoDevicePrimaryUser',
      'puavoDeviceHWInfo',
      'puavoPurchaseDate',
      'puavoWarrantyEndDate',
      'puavoPurchaseLocation',
      'puavoPurchaseURL',
      'puavoSupportContract',
      'puavoLocationName',
      'puavoSchool',
      'puavoDeviceStatus',
      'puavoImageSeriesSourceURL',
      'puavoPrinterDeviceURI',
      'puavoDefaultPrinter',
      'puavoDeviceDefaultAudioSource',
      'puavoDeviceDefaultAudioSink',
      'puavoAllowGuest',
      'puavoPersonallyAdministered',
      'puavoAutomaticImageUpdates',
      'puavoPersonalDevice',
      'puavoLatitude',
      'puavoLongitude',
      'puavoTimezone',
      'puavoDeviceAutoPowerOffMode',
      'puavoDeviceOnHour',
      'puavoDeviceOffHour',
      'puavoDeviceReset',
      'puavoDeviceExpirationTime',
      'authTimestamp',      # LDAP operational attribute
      'createTimestamp',    # LDAP operational attribute
      'modifyTimestamp'     # LDAP operational attribute
    ].freeze
  end

  # Retrieves a list of all devices in the specified school
  def self.get_devices_in_school(school_dn, custom_attributes=nil)
    return Device.search_as_utf8(:filter => "(puavoSchool=#{school_dn})",
                                 :scope => :one,
                                 :attributes => custom_attributes ? custom_attributes : DEVICE_ATTRIBUTES)
  end

  def self.get_server_attributes()
    return (self.get_device_attributes() + ["puavoDeviceAvailableImage"] - ["puavoDevicePrimaryUser"]).freeze
  end

  # Used in devices controller and organisations controller, when generating a list of devices
  # for the SuperTable. Used to retrieve primary user data, because we will not send a list of
  # all users to the client side.
  def self.fill_in_device_primary_users(raw_devices)
    cache = {}

    raw_devices.each do |_, d|
      user_dn = d.fetch('puavoDevicePrimaryUser', [nil])[0]
      next unless user_dn

      unless cache.include?(user_dn)
        begin
          cache[user_dn] = User.find(user_dn)
        rescue StandardError
          cache[user_dn] = nil
        end
      end

      user = cache[user_dn]

      if user
        d['puavoDevicePrimaryUser'] = {
          valid: true,
          link: "/users/#{user.primary_school.id}/users/#{user.id}",
          title: "#{user.uid} (#{user.givenName} #{user.sn})"
        }
      else
        d['puavoDevicePrimaryUser'] = {
          valid: false,
          dn: user_dn,
        }
      end
    end
  end

  def self.format_device_primary_user(dn, school_id)
    begin
      u = User.find(dn)

      # The DN is valid
      return {
        valid: true,
        link: "/users/#{school_id}/users/#{u.id}",
        title: "#{u.uid} (#{u.givenName} #{u.sn})"
      }
    rescue StandardError
      # The DN is not valid, indicate it on the table
      return {
        valid: false,
        dn: dn,
      }
    end
  end

  def self.device_school_change_list(owner, user=nil, current_school_dn=nil)
    # Get a list of schools for the mass tool. I wanted to do this with AJAX
    # calls, getting the list from puavo-rest with the new V4 API, but fetch()
    # and CORS and other domains just won't cooperate...

    schools = School.search_as_utf8(:filter => '', :attributes => ['displayName', 'cn']).collect do |s|
        [s[0], s[1]['displayName'][0], s[1]['cn'][0]]
    end.sort do |a, b|
        # Sort alphabetically
        a[1].downcase <=> b[1].downcase
    end

    unless owner
      # School admins can only transfer devices between the schools they're admins of
      admin_schools = Set.new(Array(user.puavoAdminOfSchool || []).map { |dn| dn.to_s })
      schools.delete_if { |s| !admin_schools.include?(s[0]) }
    end

    if current_school_dn
      # Don't show the current school on the list. Not used on the organisation devices page.
      schools.delete_if { |s| s[0] == current_school_dn }
    end

    schools
  end

  # Resets (clears) the primary user of all devices this user is the primary user of.
  # Does not handle exceptions; if even one of the devices fail, the operation stops.
  def self.clear_device_primary_user(user_dn)
    Device.find(
      :all,
      attribute: 'puavoDevicePrimaryUser',
      value: user_dn.to_s
    ).each do |device|
      device.puavoDevicePrimaryUser = nil
      device.save!
    end
  end

  def self.group_image_filenames_by_release(releases)
    return nil unless Puavo::CONFIG.include?('known_release_groups')

    # Group the filenames by known release names
    known_release_groups = Puavo::CONFIG.fetch('known_release_groups', {}).freeze
    by_release = {}

    known_release_groups.keys.each { |name| by_release[name] = [] }

    releases.keys.group_by do |r|
      known_release_groups.each do |name, display_name|
        if r.include?("-#{name}-")
          by_release[name] << r
          break
        end
      end
    end

    # Ensure the filenames are sorted by the timestamp in the image filename,
    # then list the 5 most recent images for each release
    by_release = by_release.transform_values do |entries|
      entries.sort.reverse.take(5)
    end

    # Convert the mapping keys into human-readable names
    by_release.transform_keys { |key| known_release_groups[key] }
  end
end
