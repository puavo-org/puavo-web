class DeviceStatisticsController < ApplicationController
  before_action :find_school

  ACCEPTED_TYPES = ['fatclient', 'thinclient', 'laptop']

  # GET /devices
  def index
    # The routes in routes.rb call school_statistics() or organisation_statistics()
    # directly, so this controller does not have an "index".
  end

  def school_statistics
    # All devices...

    raw = DevicesHelper.get_devices_in_school(
      @school.dn,
      custom_attributes=['puavoId', 'puavoHostname', 'puavoDeviceType', 'puavoDeviceHWInfo'])

    # Remove those we don't care about
    raw.reject! { |d| !ACCEPTED_TYPES.include?(d[1]['puavoDeviceType'][0]) }

    # Remove those without device information
    raw.reject! { |d| !d[1].include?('puavoDeviceHWInfo') }
    @total_devices = raw.count

    # Convert the raw device array into something that can be counted more easily
    @devices = []

    raw.each do |dn, r|
      @devices << {
        id: r['puavoId'][0],
        name: r['puavoHostname'][0],
        image: JSON.parse(r['puavoDeviceHWInfo'][0])['this_image'],
        school: school,
      }
    end

    # Count the images
    @image_stats = count_images(@devices)

    respond_to do |format|
      format.html { render :action => 'school_index' }
    end
  end

  def organisation_statistics
    return if redirected_nonowner_user?

    @total_devices = 0
    @devices = []

    School.all.each do |school|
      raw = DevicesHelper.get_devices_in_school(
        school.dn,
        custom_attributes=['puavoId', 'puavoHostname', 'puavoDeviceType', 'puavoDeviceHWInfo'])

      # Remove those we don't care about
      raw.reject! { |d| !ACCEPTED_TYPES.include?(d[1]['puavoDeviceType'][0]) }

      # Remove those without device information
      raw.reject! { |d| !d[1].include?('puavoDeviceHWInfo') }
      @total_devices += raw.count

      # Convert the raw device array into something that can be counted more easily
      raw.each do |dn, r|
        @devices << {
          id: r['puavoId'][0],
          name: r['puavoHostname'][0],
          image: JSON.parse(r['puavoDeviceHWInfo'][0])['this_image'],
          school: school,
        }
      end
    end

    # Count the images
    @image_stats = count_images(@devices)

    respond_to do |format|
      format.html { render :action => 'organisation_index' }
    end

  end

  private

  def count_images(devices)
    return [] if devices.empty?

    # split by image name
    images = {}

    devices.each do |d|
      img = d[:image]

      unless images.include?(img)
        images[img] = {
          uses: 0,
          devices: []
        }
      end

      images[img][:uses] += 1
      images[img][:devices] << d    # copy the devices so we can list them
    end

    total = devices.count.to_f

    # convert the hash to array
    out = []

    images.each do |name, stats|
      out << {
        name: name,
        uses: stats[:uses],
        percentage: ((stats[:uses].to_f / total) * 100.0).round(1),
        devices: stats[:devices]
      }
    end

    # sort the images by their name (they have a Y-M-D timestamp)
    out.sort! do |a, b|
      b[:name] <=> a[:name]
    end

    # also sort the devices under each image by their hostname
    out.each do |o|
      o[:devices].sort! do |da, db|
        da[:name].downcase <=> db[:name].downcase
      end
    end
  end
end
