require 'http'

module PuavoRest

  class Certs < PuavoSinatra

    # Deprecated, but should be supported for a long time
    # for all Ubuntu Trusty / Debian Stretch versions of puavo-os.
    post "/v3/hosts/certs/sign" do
      auth :basic_auth

      host = Host.by_dn(User.current.dn)
      unless host then
        status 404
        return json({ 'error' => 'could not find the connecting host' })
      end

      org = Host.organisation
      org_key = org.domain.split("." + PUAVO_ETC.topdomain).first

      fqdn = host.hostname + "." + org.domain

      res = HTTP.basic_auth(:user => LdapModel.settings[:credentials][:dn],
                            :pass => LdapModel.settings[:credentials][:password])
        .delete(CONFIG["puavo_ca"] + "/certificates/revoke.json",
                :json => { "fqdn" => fqdn } )

      if res.code != 200 && res.code != 404
        raise InternalError, "Unable to revoke certificate"
      end

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

      json res.parse["certificate"]
    end

    post '/v3/hosts/certs/sign_with_version' do
      auth :basic_auth

      certificate_request = json_params['certificate_request']
      halt(400, json(:error => 'no certificate request parameter')) \
        unless certificate_request.kind_of?(String) \
                 && !certificate_request.empty?
      version = json_params['version']
      halt(400, json(:error => 'no version parameter')) \
        unless version.kind_of?(String) && !version.empty?

      host = Host.by_dn( LdapModel.settings[:credentials][:dn] )
      unless host then
        status 404
        return json({ 'error' => 'could not find the connecting host' })
      end

      org = Host.organisation
      org_key = org.domain.gsub(".#{ PUAVO_ETC.topdomain }", '')

      fqdn = "#{ host.hostname }.#{ org.domain }"

      res = puavo_ca_request.delete(
              "#{ CONFIG['puavo_ca'] }/certificates/revoke.json",
              :json => { 'fqdn' => fqdn, 'version' => version })
      raise InternalError, 'Unable to revoke certificate' \
        unless res.code == 200 || res.code == 404

      res = puavo_ca_request.post("#{ CONFIG['puavo_ca'] }/certificates.json",
              :json => {
                'org' => org_key,
                'certificate' => {
                  'fqdn'                     => fqdn,
                  'host_certificate_request' => certificate_request,
                  'version'                  => version }})

      raise InternalError, "Unable to sign certificate" \
        unless res.code.to_s.match(/^2/)

      parsed_response = res.parse
      raise 'no certificate structure returned by puavo-ca' \
        unless parsed_response.kind_of?(Hash)
      raise 'no host certificate returned by puavo-ca' \
        unless parsed_response['host_certificate'].kind_of?(Hash)
      raise 'no organisation ca certificate bundle returned by puavo-ca' \
        unless parsed_response['org_ca_certificate_bundle'].kind_of?(Hash)
      raise 'no root ca certificate returned by puavo-ca' \
        unless parsed_response['root_ca_certificate'].kind_of?(Hash)

      return json(parsed_response)
    end

    def puavo_ca_request
      dn       = LdapModel.settings[:credentials][:dn]
      password = LdapModel.settings[:credentials][:password]
      HTTP.basic_auth(:user => dn, :pass => password)
    end
  end
end
