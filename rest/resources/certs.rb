require 'http'

module PuavoRest

  class Certs < PuavoSinatra
    post '/v3/hosts/certs/sign' do
      auth :basic_auth

      certificate_request = json_params['certificate_request']
      halt(400, json(:error => 'no certificate request parameter')) \
        unless certificate_request.kind_of?(String) \
                 && !certificate_request.empty?

      host = Host.by_dn( LdapModel.settings[:credentials][:dn] )
      unless host then
        status 404
        return json({ 'error' => 'could not find the connecting host' })
      end

      org = Host.organisation
      org_key = org.domain.gsub(".#{ PUAVO_ETC.topdomain }", '')

      fqdn = "#{ host.hostname }.#{ org.domain }"
      revoke_params = { 'fqdn' => fqdn }
      revoke_params[:version] = json_params[:version] \
        unless json_params[:version].nil?

      res = puavo_ca_request.delete(
              "#{ CONFIG['puavo_ca'] }/certificates/revoke.json",
              :json => revoke_params)
      unless res.code == 200 || res.code == 404 then
        # XXX we should get a proper (detailed) error message to log
        raise InternalError, "Unable to revoke certificate: #{ res.parse }"
      end

      certificate_params = {
        :fqdn                     => fqdn,
        :host_certificate_request => certificate_request,
        :organisation             => org_key,
      }
      certificate_params[:version] \
        = json_params[:version] unless json_params[:version].nil?

      res = puavo_ca_request.post("#{ CONFIG['puavo_ca'] }/certificates.json",
              :json => { 'certificate' => certificate_params })

      # XXX we should get a proper (detailed) error message to log
      raise InternalError, 'Unable to sign certificate' \
        unless res.code.to_s.match(/^2/)

      parsed_response = res.parse
      raise 'no certificate structure returned by puavo-ca' \
        unless parsed_response.kind_of?(Hash)
      raise 'no host certificate returned by puavo-ca' \
        unless parsed_response['certificate'].kind_of?(String)
      raise 'no organisation ca certificate bundle returned by puavo-ca' \
        unless parsed_response['org_ca_certificate_bundle'].kind_of?(String)
      raise 'no root ca certificate returned by puavo-ca' \
        unless parsed_response['root_ca_certificate'].kind_of?(String)

      return json(parsed_response)
    end

    def puavo_ca_request
      dn       = LdapModel.settings[:credentials][:dn]
      password = LdapModel.settings[:credentials][:password]
      HTTP.basic_auth(:user => dn, :pass => password)
    end
  end
end
