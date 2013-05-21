module PuavoRest

class SessionsModel
end


# Desktop login sessions
class Sessions < LdapSinatra

  auth Credentials::BootServer

  before do
    @m = LtspServersModel.from_domain @organisation_info["domain"]
  end

  def generate_uuid
    4
  end

  # Create new desktop session
  #
  # @param hostname
  # @param username
  post "/v3/sessions" do
    hostname = params["hostname"]
    session = {
      "uuid" => generate_uuid,
    }

    device = new_model(DevicesModel).by_hostname(hostname)
    if device.nil?
      halt 400, json("error" => "Unknown device #{ hostname }")
    end

    if device["image"]
      puts "Using device's own #{ device["image"] } for #{ hostname }"
      session["ltsp_server"] = @m.most_idle(device["image"]).first
      halt json session
    end

    school = new_model(SchoolsModel).by_dn device["school_dn"]
    if school["image"]
      session["ltsp_server"] = @m.most_idle(school["image"]).first
      puts "Using school's image #{ school["image"] } for #{ hostname }"
      halt json session
    end

    organisation = new_model(Organisations).by_dn @organisation_info["base"]
    if organisation["image"]
      puts "Using organisation's image #{ organisation["image"] } for #{ hostname }"
      session["ltsp_server"] = @m.most_idle(organisation["image"]).first
      halt json session
    end

    session["ltsp_server"] = @m.most_idle.first
    json session
  end

  get "/v3/sessions/:uuid" do
  end

end
end
