class DeviceStatisticsController < ApplicationController
  before_action :find_school

  BYTES_TO_GIB = 1024 * 1024 * 1024

  # GET /devices
  def index
    # Not reached
  end

  def school_statistics

    devices = Device.find(:all,
                          :attribute => 'puavoSchool',
                          :value => @school.dn)

    @with_info, @without_info = gather_devices(devices, school)

    @total_devices = @with_info.count + @without_info.count

    @image_stats = count_images(@with_info)

    @with_info.sort! do |a, b|
      a[:name].downcase <=> b[:name].downcase
    end

    # Sort the devices without hardware info. On organisation statistics page
    # the table can be sorted by the user, but on the school page there is
    # no table, only an unsortable list.
    @without_info.sort! do |a, b|
      a[:name].downcase <=> b[:name].downcase
    end

    respond_to do |format|
      format.html { render :action => 'school_index' }
    end
  end

  def organisation_statistics
    @with_info = []
    @without_info = []

    School.all.each do |school|
      # all devices in this school
      school_devices = Device.find(:all,
                                   :attribute => 'puavoSchool',
                                   :value => school.dn)

      with, without = gather_devices(school_devices, school)

      @with_info += with
      @without_info += without
    end

    @image_stats = count_images(@with_info)

    @total_devices = @with_info.count + @without_info.count

    # sort by hostname
    @with_info.sort! do |a, b|
      a[:name].downcase <=> b[:name].downcase
    end

    respond_to do |format|
      format.html { render :action => 'organisation_index' }
    end
  end

  private

  def gather_devices(all_devices, school)
    with = []
    without = []

    all_devices.each do |device|
      next unless ['fatclient', 'thinclient', 'laptop'].include?(device.puavoDeviceType)

      unless device.puavoDeviceHWInfo
        without << {
          name: device.puavoHostname,
          type: device.puavoDeviceType,
          device: device,             # for clickable links
          school: school,             # ditto
        }

        next
      end

      hwinfo = JSON.parse(device.puavoDeviceHWInfo)

      data = {
        device: device,             # for clickable links
        school: school,             # ditto

        # --------
        name: device.puavoHostname,
        type: device.puavoDeviceType,
        # --------
        timestamp: hwinfo['timestamp'],
        image: hwinfo['this_image'],
        memory: hwinfo['memory'].sum { |slot| slot['size'].to_i },
        cpu_count: hwinfo['processorcount'],
        cpu_name: hwinfo['processor0'],
        hard_drive: ((hwinfo['blockdevice_sda_size'] || 0) / BYTES_TO_GIB).to_i
      }

      if data[:memory] == 0
        # some devices have no listed memory slots for some reason
        data[:memory] = hwinfo['memorysize_mb'].to_i
      end

      with << data
    end

    return with, without
  end

  def count_images(devices)
    return [] if devices.empty?

    # split by image name
    images = {}

    devices.each do |s|
      i = s[:image]

      unless images.include?(i)
        images[i] = {
          uses: 0,
          devices: []
        }
      end

      images[i][:uses] += 1
      images[i][:devices] << s    # copy the devices so we can list them
    end

    total = devices.count.to_f

    # convert the hash to array
    out = []

    images.each do |name, s|
      out << {
        name: name,
        uses: s[:uses],
        percentage: ((s[:uses].to_f / total) * 100.0).round(1),
        devices: s[:devices]
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
