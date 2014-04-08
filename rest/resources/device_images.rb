
module PuavoRest
class DeviceImages < LdapSinatra

  def organisation_image
    Organisation.current(:no_cache).get_own(:preferred_image)
  end


  def all_images
    images = [organisation_image]

    [School, Device, BootServer, LtspServer].each do |model|
      model.all.each do |s|
          images.push s.get_own(:preferred_image)
        end
    end

    images
  end

  def by_boot_servers(boot_servers)
    images = [organisation_image]

    boot_servers.each do |boot_server|
      images.push(boot_server.get_own(:preferred_image))

      boot_server.schools.each do |school|
        images.push(school.get_own(:preferred_image))

        school.devices.each do |device|
          images.push(device.get_own(:preferred_image))
        end

        school.ltsp_servers.each do |ltsp_server|
          images.push(ltsp_server.get_own(:preferred_image))
        end

      end
    end

    images
  end

  # List all images that are in use in the current organisation
  get "/v3/device_images" do
    auth :basic_auth, :server_auth

      boot_servers = Array(params["boot_server"]).map do |hostname|
        BootServer.by_hostname!(hostname)
      end

    if boot_servers.empty?
      images = all_images
    else
      images = by_boot_servers(boot_servers)
    end

    images.compact!
    images.uniq!
    images.sort!
    json images
  end

end
end
