# The OpenID Connect userinfo endpoint

module PuavoRest
module OAuth2
  def oidc_handle_userinfo
    oauth2 scopes: ['openid', 'profile'], audience: 'puavo-rest-userinfo'
    auth :oauth2_token

    request_id = make_request_id()

    access_token = LdapModel.settings[:credentials][:access_token]

    rlog.info("[#{request_id}] Returning userinfo data for user \"#{access_token['user_dn']}\" in organisation \"#{access_token['organisation_domain']}\"")

    begin
      organisation = Organisation.by_domain(access_token['organisation_domain'])
      LdapModel.setup(organisation: organisation, credentials: CONFIG['server'])

      user = PuavoRest::User.by_dn(access_token['user_dn'])

      if user.nil?
        rlog.error("[#{request_id}] Cannot find user #{access_token['user_dn']}")
        return json_error('access_denied', request_id: request_id)
      end

      # Locked users cannot access any resources
      if user.locked || user.removal_request_time
        rlog.error("[#{request_id}] The target user (#{user.username}) is locked or marked for deletion")
        return json_error('access_denied', request_id: request_id)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not log in and retrieve the target user: #{e}")
      return json_error('server_error', request_id: request_id)
    end

    begin
      user_data = gather_user_data(request_id, access_token['scopes'], organisation, user)
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not gather the user data for the token: #{e}")
      return json_error('server_error', request_id: request_id)
    end

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(user_data)
  end

  def gather_user_data(request_id, scopes, organisation, user)
    out = {}
    school_cache = {}

    if scopes.include?('profile')
      # Try to extract the modification timestamp from the LDAP operational attributes
      begin
        extra = User.raw_filter("ou=People,#{organisation['base']}", "(puavoId=#{user.id})", ['modifyTimestamp'])
        updated_at = Time.parse(extra[0]['modifyTimestamp'][0]).to_i
      rescue StandardError => e
        rlog.warn("[#{request_id}] Cannot determine the user's last modification time: #{e}")
        updated_at = nil
      end
    end

    # Include LDAP DNs in the response?
    has_ldap = scopes.include?('puavo.read.userinfo.ldap')

    if scopes.include?('profile')
      # Standard claims
      out['given_name'] = user.first_name
      out['family_name'] = user.last_name
      out['name'] = "#{user.first_name} #{user.last_name}"
      out['preferred_username'] = user.username
      out['updated_at'] = updated_at unless updated_at.nil?
      out['locale'] = user.locale
      out['timezone'] = user.timezone

      # Puavo-specific claims
      out['puavo.uuid'] = user.uuid
      out['puavo.puavoid'] = user.puavo_id.to_i
      out['puavo.ldap_dn'] = user.dn if has_ldap
      out['puavo.external_id'] = user.external_id if user.external_id
      out['puavo.learner_id'] = user.learner_id if user.learner_id
      out['puavo.roles'] = user.roles
    end

    if scopes.include?('email')
      # Prefer the primary email address if possible
      unless user.primary_email.nil?
        out['email'] = user.primary_email
        out['email_verified'] = user.verified_email && user.verified_email.include?(user.primary_email)
      else
        unless user.verified_email.empty?
          # This should not really happen, as the first verified email is
          # also the primary email
          out['email'] = user.verified_email[0]
          out['email_verified'] = true
        else
          # Just pick the first available address
          if user.email && !user.email.empty?
            out['email'] = user.email[0]
            out['email_verified'] = false
          else
            out['email'] = nil
            out['email_verified'] = false
          end
        end
      end
    end

    if scopes.include?('phone')
      out['phone_number'] = user.telephone_number[0] unless user.telephone_number.empty?
    end

    if scopes.include?('puavo.read.userinfo.schools')
      schools = []

      user.schools.each do |s|
        school_cache[s.dn] = s

        school = {
          'name' => s.name,
          'abbreviation' => s.abbreviation,
          'puavoid' => s.puavo_id.to_i,
          'external_id' => s.external_id,
          'school_code' => s.school_code,
          'oid' => s.school_oid,
          'primary' => user.primary_school_dn == s.dn,
        }

        school['ldap_dn'] = s.dn if has_ldap

        schools << school
      end

      out['puavo.schools'] = schools
    end

    if scopes.include?('puavo.read.userinfo.groups')
      have_schools = scopes.include?('puavo.read.userinfo.schools')
      groups = []

      user.groups.each do |g|
        group = {
          'name' => g.name,
          'abbreviation' => g.abbreviation,
          'puavoid' => g.id.to_i,
          'external_id' => g.external_id,
          'type' => g.type,
        }

        group['ldap_dn'] = g.dn if has_ldap
        group['school_abbreviation'] = get_school(g.school_dn, school_cache).abbreviation if have_schools

        groups << group
      end

      out['puavo.groups'] = groups
    end

    if scopes.include?('puavo.read.userinfo.organisation')
      org = {
        'name' => organisation.name,
        'domain' => organisation.domain,
      }

      org['ldap_dn'] = organisation.dn if has_ldap

      out['puavo.organisation'] = org
    end

    if scopes.include?('puavo.read.userinfo.admin')
      out['puavo.is_organisation_owner'] = organisation.owner.include?(user.dn)

      if scopes.include?('puavo.read.userinfo.schools')
        out['puavo.admin_in_schools'] = user.admin_of_school_dns.collect do |dn|
          get_school(dn, school_cache).abbreviation
        end
      end
    end

    if scopes.include?('puavo.read.userinfo.security')
      out['puavo.mfa_enabled'] = user.mfa_enabled == true
      out['puavo.opinsys_admin'] = nil    # TODO: Future placeholder (for now)
    end

    school_cache = nil
    out
  end

private

  # School searches are slow, so cache them
  def get_school(dn, cache)
    unless cache.include?(dn)
      cache[dn] = School.by_dn(dn)
    end

    cache[dn]
  end
end   # module OAuth2
end   # module PuavoRest
