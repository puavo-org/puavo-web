module PuavoRest

  class Certs < PuavoSinatra

    post "/v3/hosts/certs/sign" do
      auth :basic_auth

      host = Host.by_hostname!(json_params["hostname"])

      org = Host.organisation
      org_key = org.domain.split("." + PUAVO_ETC.topdomain).first

      fqdn = host.hostname + "." + org.domain

      res = HTTP.basic_auth(:user => LdapModel.settings[:credentials][:dn],
                            :pass => LdapModel.settings[:credentials][:password])
        .post(CONFIG["puavo_ca"] + "/certificates.json",
              :json => {
                "org" => org_key,
                "certificate" => {
                  "fqdn" => fqdn,
                  "host_certificate_request" => json_params["certificate_request"] } } )

      if !res.code.to_s.match(/^2/)
        raise InternalError, "Unable to sign certificate"
      end

      json res.parse
    end

  end
end
