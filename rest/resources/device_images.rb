
module PuavoRest
class DeviceImages < LdapSinatra

  # List all images that are in use in the current organisation
  get "/v3/device_images" do
    auth :basic_auth, :server_auth
    images = []
    images.push Organisation.current.preferred_image

    school_limit = nil

    Array(params["boot_server"]).each do |b|
      BootServer.by_hostname!(b).school_dns.each do |dn|
        school_limit ||= {}
        school_limit[dn.downcase] = true
      end
    end

    School.all.each do |s|
      if school_limit.nil? || school_limit[s.dn.downcase]
        # Use get_own to avoid fallbacking to school or organisation
        images.push s.get_own(:preferred_image)
      end
    end

    Device.all.each do |d|
      if school_limit.nil? || school_limit[d.school_dn.downcase]
        images.push d.get_own(:preferred_image)
      end
    end

    images.compact!
    images.uniq!
    json images
  end

end
end
