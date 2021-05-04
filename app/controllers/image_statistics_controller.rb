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

    @total_devices = devices.count
    @image_stats = count_images(devices)

    respond_to do |format|
      format.html   # all_images.html.erb
    end
  end

  # GET /schools/:id/images
  def school_images
    devices = process_school_devices(@school)
    @total_devices = devices.count
    @image_stats = count_images(devices)

    respond_to do |format|
      format.html   # school_images.html.erb
    end
  end

  private

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

    releases = get_releases()

    # convert the hash to array
    out = []

    images.each do |name, stats|
      out << {
        name: name,
        release: releases[name.gsub('.img', '')] || nil,
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
