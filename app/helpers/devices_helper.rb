# frozen_string_literal: true

require 'set'

module DevicesHelper
  include Puavo::Helpers

  # TODO: Is this actually used anywhere?
  def classes(device)
    Device.allowed_classes.map do |r|
      "<div><label><input #{'checked="checked"' if device.classes.include?(r)}" \
        "id='devices_#{r}' name='device[classes][]' type='checkbox' value='#{r}' />#{r}</label></div>\n"
    end
  end

  # Called from shared/_linux_device_information.html.erb (and maybe elsewhere too)
  # (Noted here because this method name is hard to grep)
  def title(device)
    if device.classes.include?('puavoNetbootDevice')
      t('shared.terminal_title')
    elsif device.classes.include?('puavoPrinter')
      t('shared.printer_title')
    elsif device.classes.include?('puavoServer')
      t('shared.server_title')
    else
      t('shared.title')
    end
  end

  # Extracts the printer model name from the embedded PPD file if it's set
  def model_name_from_ppd(ppd)
    if ppd.nil?
      I18n.t('helpers.ppd_file.no_file')
    elsif (match_data = ppd.match(/\*ModelName:(.*)\n/))
      match_data[1].lstrip.gsub('"', '')
    else
      I18n.t('helpers.ppd_file.cannot_detect_filetype')
    end
  end

  def self.get_device_attributes
    %w[
      authTimestamp
      createTimestamp
      description
      macAddress
      modifyTimestamp
      puavoAllowGuest
      puavoAutomaticImageUpdates
      puavoConf
      puavoDefaultPrinter
      puavoDeviceAutoPowerOffMode
      puavoDeviceCurrentImage
      puavoDeviceDefaultAudioSink
      puavoDeviceDefaultAudioSource
      puavoDeviceExpirationTime
      puavoDeviceHWInfo
      puavoDeviceImage
      puavoDeviceKernelArguments
      puavoDeviceKernelVersion
      puavoDeviceManufacturer
      puavoDeviceModel
      puavoDeviceMonitorsXML
      puavoDeviceOffHour
      puavoDeviceOnHour
      puavoDevicePrimaryUser
      puavoDeviceReset
      puavoDeviceStatus
      puavoDeviceType
      puavoDeviceXrandr
      puavoDisplayName
      puavoHostname
      puavoId
      puavoImageSeriesSourceURL
      puavoLatitude
      puavoLocationName
      puavoLongitude
      puavoNotes
      puavoPersonalDevice
      puavoPersonallyAdministered
      puavoPrinterDeviceURI
      puavoPurchaseDate
      puavoPurchaseLocation
      puavoPurchaseURL
      puavoSchool
      puavoSupportContract
      puavoTag
      puavoTimezone
      puavoWarrantyEndDate
      serialNumber
    ].freeze
  end

  # Retrieves a list of all devices in the specified school
  def self.get_devices_in_school(school_dn, custom_attributes: nil)
    Device.search_as_utf8(
      filter: "(puavoSchool=#{school_dn})",
      scope: :one,
      attributes: custom_attributes || get_device_attributes
    )
  end

  def self.get_server_attributes
    (self.get_device_attributes + ['puavoDeviceAvailableImage'] - ['puavoDevicePrimaryUser']).freeze
  end

  # Used in devices controller and organisations controller, when generating a list of devices
  # for the SuperTable. Used to retrieve primary user data, because we will not send a list of
  # all users to the client side.
  def self.fill_in_device_primary_users(raw_devices)
    cache = {}

    raw_devices.each do |_, dev| # rubocop:disable Style/HashEachMethods
      user_dn = dev.fetch('puavoDevicePrimaryUser', [nil])[0]
      next unless user_dn

      unless cache.include?(user_dn)
        begin
          cache[user_dn] = User.find(user_dn)
        rescue StandardError
          cache[user_dn] = nil
        end
      end

      user = cache[user_dn]

      dev['puavoDevicePrimaryUser'] =
        if user
          {
            valid: true,
            link: "/users/#{user.primary_school.id}/users/#{user.id}",
            title: "#{user.uid} (#{user.givenName} #{user.sn})"
          }
        else
          {
            valid: false,
            dn: user_dn
          }
        end
    end
  end

  def self.format_device_primary_user(user_dn, school_id)
    user = User.find(user_dn)

    # The DN is valid
    {
      valid: true,
      link: "/users/#{school_id}/users/#{user.id}",
      title: "#{user.uid} (#{user.givenName} #{user.sn})"
    }
  rescue StandardError
    # The DN is not valid, indicate it on the table
    {
      valid: false,
      dn: user_dn
    }
  end

  def self.device_school_change_list(owner, user = nil, current_school_dn = nil)
    # Get a list of schools for the mass tool. I wanted to do this with AJAX
    # calls, getting the list from puavo-rest with the new V4 API, but fetch()
    # and CORS and other domains just won't cooperate...

    schools = School.search_as_utf8(filter: '', attributes: %w[displayName cn])
                    .collect { |s| [s[0], s[1]['displayName'][0], s[1]['cn'][0]] }
                    .sort { |a, b| a[1].downcase <=> b[1].downcase }

    unless owner
      # School admins can only transfer devices between the schools they're admins of
      admin_schools = Set.new(Array(user.puavoAdminOfSchool || []).map(&:to_s))
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

    known_release_groups.each_key { |name| by_release[name] = [] }

    releases.keys.group_by do |r|
      known_release_groups.each_key do |name|
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
