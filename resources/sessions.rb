module PuavoRest

class SessionsModel
end


# Desktop login sessions
class Sessions < LdapSinatra

  auth Credentials::BootServer

  def generate_uuid
    4
  end

  # Create new desktop session
  #
  # @param hostname
  # @param username
  post "/v3/sessions" do

    device = new_model(DevicesModel).by_hostname(params["hostname"])
    if device.nil?
      not_found_ "Unknown device #{ params["hostname"] }"
    end

    session = device.dup
    session[:uuid] = generate_uuid

    if session["image"]
      halt json session
    end

    school = new_model(SchoolsModel).by_dn device["school_dn"]
    halt json school

    json ":(" => session
  end

  get "/v3/sessions/:uuid" do
  end

end
end
