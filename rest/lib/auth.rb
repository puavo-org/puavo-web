require "puavo"

require "thread"
require "base64"
require "gssapi"
require "gssapi/lib_gssapi"

require_relative "./krb5-gssapi"

require_relative './oauth2_audit'

module PuavoRest

class PuavoSinatra < Sinatra::Base

  include PuavoRest::Audit

  def basic_auth
    return if not env["HTTP_AUTHORIZATION"]
    type, data = env["HTTP_AUTHORIZATION"].split(" ", 2)
    if type == "Basic"
      plain = Base64.decode64(data)
      username, password = plain.split(":")

      credentials = { :password => password  }
      if LdapModel.is_dn(username)
        credentials[:dn] = username
      else
        credentials[:username] = username
      end
      rlog.info("using basic auth #{ credentials[:dn] ? "with dn" : "with uid" }")
      return credentials
    end
  end

  def from_post
    return if env["REQUEST_METHOD"] != "POST"
    return {
      :username => params["username"].split("@").first,
      :password => params["password"]
    }
  end

  def pw_mgmt_server_auth
    if CONFIG["password_management"]
      return {
        :dn => PUAVO_ETC.ds_pw_mgmt_dn,
        :password => PUAVO_ETC.ds_pw_mgmt_password
      }
    else
      rlog.error('cannot use password management auth on cloud or bootserver installation')
      return
    end
  end

  # Email address changing/verification using the public profile form
  def email_mgmt_server_auth
    if CONFIG['email_management']
      return {
        :dn => PUAVO_ETC.ds_email_mgmt_dn,
        :password => PUAVO_ETC.ds_email_mgmt_password
      }
    else
      rlog.error('cannot use email management auth on cloud or bootserver installation')
      return
    end
  end

  # MFA activation state changing
  def mfa_mgmt_server_auth
    if CONFIG['mfa_management']
      return {
        :dn => CONFIG['mfa_management']['server']['username'],
        :password => CONFIG['mfa_management']['server']['password']
      }
    else
      rlog.error('cannot use MFA management auth on cloud or bootserver installation')
      return
    end
  end

  # Pick bootserver credentials when Header 'Authorization: Bootserver' is set
  def server_auth
    if not CONFIG["bootserver"]
      rlog.error('cannot use bootserver auth on cloud installation')
      return
    end

    if env["HTTP_AUTHORIZATION"].to_s.downcase == "bootserver"
      return CONFIG["server"]
    end
  end

  # In an old version bootserver authentication was picked when no other
  # authentication methods were available. But that conflicted with the
  # kerberos authentication. This is now legacy and will removed in future.
  def legacy_server_auth
    if not CONFIG["bootserver"]
      rlog.error('cannot use bootserver auth on cloud installation')
      return
    end

    # In future we will only use server based authentication if 'Authorization:
    # Bootserver' is set. Otherwise we will assume Kerberos authentication.
    if env["HTTP_AUTHORIZATION"].to_s.downcase != "bootserver"
      rlog.warn("WARNING!  Using deprecated bootserver authentication without the Header 'Authorization: Bootserver'")
    end

    ## Helper to sweep out lecagy calls from tests
    # if ENV["RACK_ENV"] == "test"
    #   puts "Legacy legacy_server_auth usage from:"
    #   puts caller[0..5]
    #   puts
    # end

    return CONFIG["server"]
  end

  # OAuth 2 self-validating access token
  def oauth2_token
    # If your endpoint supports OAuth2 tokens, you have to specify the parameters for it
    return if @oauth2_params.nil?

    return unless request.env.include?('HTTP_AUTHORIZATION')

    # If there's an authorization header, see if it looks like a bearer token
    authorization = request.env['HTTP_AUTHORIZATION'].split(' ')

    return if authorization.count != 2 ||
              authorization[0] != 'Bearer' ||
              authorization[1].nil? ||
              authorization[1].strip.empty?

    if OAUTH2_TOKEN_VERIFICATION_PUBLIC_KEY.nil?
      rlog.error('oauth2_token(): have an authorization header that looks like a bearer token, but the OAuth2 token key is nil (configuration error?), refusing to process the header')
      return
    end

    # Assume it's an OAuth2 bearer token
    rlog.info('oauth2_token(): have an authorization header that looks like a bearer token, checking it')

    # See if the token is valid
    begin
      # Load the JWKS into a keyfinder
      jwks_json = JSON.parse(File.read(CONFIG['oauth2']['key_files']['public_jwks']));
      key_finder = JWT::JWK::KeyFinder.new(jwks: JWT::JWK::Set.new(jwks_json))

      et = JWT::EncodedToken.new(authorization[1])

      # Validate the passed token using the keyfinder. Try ES256 as the algorithm first because it's what we
      # use by default. If it fails, try again with RS256. If the latter fails, then fail the whole process.
      begin
        et.verify!(signature: { algorithm: 'ES256', key_finder: key_finder })
      rescue StandardError => e
        et.verify!(signature: { algorithm: 'RS256', key_finder: key_finder })
      end

      # Validate the claims
      et.verify_claims!(:iat, :exp, :nbf)
      et.verify_claims!({ iss: 'https://api.opinsys.fi', aud: @oauth2_params[:audience] })

      # RFC 9068 section 4 says this MUST be checked. The jwt gem does not put it there
      # and it does not validate it, so do it manually.
      raise "invalid header 'typ' value #{typ.inspect}; expected \"at+jwt\"" unless et.header['typ'] == 'at+jwt'

      # If we get here, the token is valid
      access_token = et.payload
    rescue StandardError => e
      # Tested
      rlog.error("OAuth2 access token validation failed: #{e}")
      rlog.error("Raw incoming token: #{authorization[1]}")

      audit_token_use(status: 'token_validation_failed',
                      error: e.class.to_s,
                      organisation: LdapModel.organisation.domain,
                      audience: @oauth2_params[:audience],
                      requested_endpoint: request.env['sinatra.route'],
                      raw_token: authorization[1],
                      request: request)

      raise InvalidOAuth2Token, user: 'invalid_token'
    end

    # Verify the LDAP ID
    ldap_ids = CONFIG['oauth2'].fetch('ldap_id', {})

    if access_token['ldap_id'].nil? || !ldap_ids.include?(access_token['ldap_id'])
      rlog.error("LDAP ID #{access_token['ldap_id'].inspect} is not valid (no mapping to LDAP credentials found)")

      audit_token_use(status: 'invalid_ldap_id',
                      organisation: LdapModel.organisation.domain,
                      token_id: access_token['jti'],
                      client_id: access_token['client_id'],
                      ldap_id: access_token['ldap_id'],
                      audience: @oauth2_params[:audience],
                      requested_scopes: access_token['scopes'],
                      requested_endpoint: request.env['sinatra.route'],
                      request: request)

      raise InvalidOAuth2Token, user: 'invalid_ldap_id'
    end

    ldap_credentials = CONFIG['oauth2']['ldap_id'][access_token['ldap_id']]

    # The access token is valid
    rlog.info("Request authorized using access token #{access_token['jti'].inspect}, " \
              "client=#{access_token['client_id'].inspect}, LDAP ID=#{access_token['ldap_id'].inspect}, " \
              "audience=#{access_token['aud'].inspect}, subject=#{access_token['sub'].inspect}, " \
              "scopes=#{access_token['scopes'].inspect}, endpoints=#{access_token.fetch('allowed_endpoints', nil).inspect}")

    rlog.info("The access token expires at #{Time.at(access_token['exp']).to_s}")

    # Verify the token contains the required scope(s) for this endoint
    token_scopes = access_token['scopes'].split(' ').to_set
    endpoint_scopes = Array(@oauth2_params[:scopes]).to_set

    endpoint_scopes.each do |s|
      unless token_scopes.include?(s)
        # Tested
        rlog.error("Token scopes do not contain the endpoint scopes (#{endpoint_scopes.to_a.inspect})")

        audit_token_use(status: 'insufficient_scope',
                        organisation: LdapModel.organisation.domain,
                        token_id: access_token['jti'],
                        client_id: access_token['client_id'],
                        audience: @oauth2_params[:audience],
                        requested_scopes: access_token['scopes'],
                        requested_endpoint: request.env['sinatra.route'],
                        request: request)

        raise InsufficientOAuth2Scope, user: 'insufficient_scope'
      end
    end

    # Is the endpoint allowed?
    verb, endpoint = request.env['sinatra.route'].split(' ')

    if access_token.include?('allowed_endpoints')
      unless access_token['allowed_endpoints'].include?(endpoint)
        # Tested
        rlog.error("This token does not permit calling the #{endpoint} endpoint")

        audit_token_use(status: 'endpoint_not_allowed',
                        organisation: LdapModel.organisation.domain,
                        token_id: access_token['jti'],
                        client_id: access_token['client_id'],
                        audience: @oauth2_params[:audience],
                        requested_scopes: access_token['scopes'],
                        requested_endpoint: request.env['sinatra.route'],
                        request: request)

        raise Forbidden, user: 'invalid_token'
      end
    end

    rlog.info('oauth2_token(): initial authorization header checks passed')

    # Good to go
    {
      dn: ldap_credentials['dn'],
      password: ldap_credentials['password'],
      access_token: access_token.freeze
    }
  end

  # This must be always the last authentication option because it is
  # initialized by the server by responding 401 Unauthorized
  def kerberos
    return if env["HTTP_AUTHORIZATION"].nil?
    auth_key = env["HTTP_AUTHORIZATION"].split()[0]
    return if auth_key.to_s.downcase != "negotiate"
    rlog.info("using kerberos authentication")
    return {
      :kerberos => Base64.decode64(env["HTTP_AUTHORIZATION"].split()[1])
    }
  end

  def auth(*auth_methods)
    if auth_methods.include?(:kerberos) && auth_methods.include?(:legacy_server_auth)
      raise "legacy server auth and kerberos cannot be used on the same resource"
    end

    auth_method = nil

    auth_methods.each do |method|
      credentials = send(method)
      next if !credentials

      if credentials[:dn].nil? && credentials[:username]
        credentials[:dn] = LdapModel.setup(:credentials => CONFIG["server"]) do
          User.resolve_dn(credentials[:username])
        end
      end

      if credentials[:dn].nil? && credentials[:kerberos].nil?
        puts "Cannot resolve #{ credentials[:username].inspect } to DN"
        raise Unauthorized,
          :user => "Could not create ldap connection. Bad/missing credentials. #{ auth_methods.inspect }",
          :meta => {
            :username => credentials[:username],
          }
      end

      credentials[:auth_method] = method
      auth_method = method
      LdapModel.setup(:credentials => credentials)
      break
    end


    if not LdapModel.connection
      raise Unauthorized,
        :user => "Could not create ldap connection. Bad/missing credentials. #{ auth_methods.inspect }"
    end

    # Further OAuth2 token validation. These cannot be made until a connection has been established.
    if auth_method == :oauth2_token
      access_token = LdapModel.settings[:credentials][:access_token]
      domain = LdapModel.organisation.domain

      # If the authentication was done using an access token and it contains a list
      # of allowed organisations, verify the domain
      if access_token.include?('allowed_organisations')
        unless access_token['allowed_organisations'].include?(domain)
          # Tested
          rlog.error("This access token does not permit calling endpoints in organisation #{domain.inspect}")

          audit_token_use(status: 'organisation_not_allowed',
                          organisation: domain,
                          token_id: access_token['jti'],
                          client_id: access_token['client_id'],
                          audience: @oauth2_params[:audience],
                          requested_scopes: access_token['scopes'],
                          requested_endpoint: request.env['sinatra.route'],
                          request: request)

          raise Forbidden, user: 'invalid_token'
        end
      end

      # External service requirements?
      if access_token.include?('required_service_dn')
        # Tested
        # TODO: The .downcase is a hack. It's needed because the model code downcases the DNs. It must be removed
        # after the model-assisted DN downcasing stupidity has been erased from existence.
        unless Organisation.current(:no_cache).external_services.include?(access_token['required_service_dn'].downcase)
          rlog.error("This token requires the service #{access_token['required_service_dn'].inspect} to be enabled in this organisation and it's not.")

          audit_token_use(status: 'required_service_not_active',
                          organisation: domain,
                          token_id: access_token['jti'],
                          client_id: access_token['client_id'],
                          audience: @oauth2_params[:audience],
                          requested_scopes: access_token['scopes'],
                          requested_endpoint: request.env['sinatra.route'],
                          required_service_dn: access_token['required_service_dn'],
                          request: request)

          raise Forbidden, user: 'invalid_token'
        end
      end

      # Log the token usage
      audit_token_use(status: 'success',
                      organisation: domain,
                      token_id: access_token['jti'],
                      client_id: access_token['client_id'],
                      ldap_id: access_token['ldap_id'],
                      audience: @oauth2_params[:audience],
                      requested_scopes: access_token['scopes'],
                      requested_endpoint: request.env['sinatra.route'],
                      request: request)
    end

    log_creds = LdapModel.settings[:credentials].dup
    log_creds.delete(:kerberos)
    log_creds.delete(:password)
    self.rlog = rlog.merge(:credentials => log_creds)
    rlog.info("authenticated through '#{ auth_method }'")

    auth_method.to_s
  end

  def oauth2(**params)
    @oauth2_params = {
      scopes: params[:scopes],
      audience: params[:audience] || 'puavo-rest-v4',
    }
  end

end
end
