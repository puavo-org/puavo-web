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
    session = {
      "uuid" => generate_uuid,
    }

    device = new_model(DevicesModel).by_hostname(params["hostname"])
    if device.nil?
      halt 400, json("error" => "Unknown device #{ params["hostname"] }")
    end

    if device["image"]
      session["ltsp_server"] = @m.most_idle(device["image"]).first
      halt json session
    end

    school = new_model(SchoolsModel).by_dn device["school_dn"]
    if school["image"]
      session["ltsp_server"] = @m.most_idle(school["image"]).first
      halt json session
    end

    json session

  end

  get "/v3/sessions/:uuid" do
  end

end
end
