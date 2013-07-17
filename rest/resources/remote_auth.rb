require "openssl"
require "addressable/uri"
# http://ruby-doc.org/stdlib-1.9.3/libdoc/openssl/rdoc/OpenSSL/HMAC.html
# h = OpenSSL::HMAC.new "foo", OpenSSL::Digest::SHA1.new

module PuavoRest
class RemoteAuth < LdapSinatra

  def respond_auth
    if params["return_to"].nil?
      raise BadInput, :user => "return_to missing"
    end

    return_url = Addressable::URI.parse(params["return_to"])
    shared_secret =  (CONFIG["remote_auth"] || {})[return_url.host]

    if shared_secret.nil?
      raise Unauthorized,
        :user => "Unknown client service #{ return_url.host }"
    end


    begin
      auth :basic_auth, :from_post, :kerberos
    rescue Unauthorized
      halt 401, erb(:login_form)
    end

    user = User.current

    query_values = (return_url.query_values || {}).merge({
      "username" => user["username"],
      "first_name" => user["first_name"],
      "last_name" => user["last_name"],
      "user_type" => user["user_type"],
      "email" => user["email"],
      "organisation_name" => user["organisation"]["name"],
      "organisation_domain" => user["organisation"]["domain"],
      "timestamp" => Time.now.to_i.to_s,
    })

    hmac = OpenSSL::HMAC.new(shared_secret, OpenSSL::Digest::SHA1.new)

    query_values.keys.sort.each do |k|
      hmac.update(query_values[k])
    end

    return_url.query_values = query_values.merge("hmac" => hmac.to_s)

    redirect return_url.to_s
  end

  get "/v3/remote_auth" do
    respond_auth
  end

  post "/v3/remote_auth" do
    respond_auth
  end

end
end
