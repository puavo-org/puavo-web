class ImageStatisticsController < ApplicationController
  before_action :find_school

  ACCEPTED_TYPES = ['fatclient', 'thinclient', 'laptop'].freeze
  CUSTOM_ATTRIBUTES = ['puavoId', 'puavoHostname', 'puavoDeviceType', 'puavoDeviceHWInfo'].freeze

  # GET /device_statistics
  def index
    # The routes in routes.rb call school_statistics() or organisation_statistics()
    # directly, so this controller does not have an "index".
  end

  # GET /all_images
  def all_images
    return if redirected_nonowner_user?

    devices = []

    School.all.each do |school|
      devices += process_school_devices(school)
    end

    make_stats(devices)

    respond_to do |format|
      format.html   # all_images.html.erb
    end
  end

  # GET /schools/:id/images
  def school_images
    make_stats(process_school_devices(@school))

    respond_to do |format|
      format.html   # school_images.html.erb
    end
  end

  private

  def make_stats(devices)
    @total_devices = devices.count
    @image_stats = count_images(devices)
  end

  def process_school_devices(school)
    out = []

    DevicesHelper.get_devices_in_school(school.dn, CUSTOM_ATTRIBUTES).each do |d|
      next unless ACCEPTED_TYPES.include?(d[1]['puavoDeviceType'][0])
      next unless d[1].include?('puavoDeviceHWInfo')

      out << {
        id: d[1]['puavoId'][0],
        name: d[1]['puavoHostname'][0],
        image: JSON.parse(d[1]['puavoDeviceHWInfo'][0])['this_image'],
        school: school,
      }
    end

    out
  end

  def count_images(devices)
    return [] if devices.empty?

    # get_releases() is defined in application_helper.rb. It reads the (optional)
    # releases.json which contains official desktop image release names.
    releases = get_releases()

    schools = {}
    images = {}

    devices.each do |d|
      img = d[:image]

      school = d[:school]

      unless schools.include?(school.cn)
        schools[school.cn] = {
          name: school.displayName,
          link: school_path(school),
        }
      end

      unless images.include?(img)
        images[img] = {
          release: releases[img.gsub('.img', '')] || nil,
          devices: [],
        }
      end

      images[img][:devices] << {
        name: d[:name],
        link: "/devices/#{d[:school].id}/devices/#{d[:id]}",
        school: school.cn,
      }
    end

    @stats = {
      schools: schools,
      images: images,
      total_devices: devices.count
    }
  end
end
