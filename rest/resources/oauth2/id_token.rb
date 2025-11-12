# frozen_string_literal: true

# OpenID Connect ID token data generator. Used during logins and when the userinfo endpoint is called.

module PuavoRest
module OAuth2
class IDTokenDataGenerator
  def initialize(request_id)
    @request_id = request_id
  end

  def generate(ldap_credentials:, domain:, user_dn:, scopes:, include_sub: false)
    # Get the organisation
    @organisation = Organisation.by_domain(domain)

    if @organisation.nil?
      $rest_log.error("[#{@request_id}] IDTokenGenerator::generate(): unknown organisation domain #{domain.inspect}")
      return 'access_denied'
    end

    # Establish connection
    LdapModel.setup(organisation: @organisation, credentials: ldap_credentials)

    # Get the user
    @user = PuavoRest::User.by_dn(user_dn)

    if @user.nil?
      $rest_log.error("[#{@request_id}] Cannot find user by DN #{user_dn.inspect}")
      return 'access_denied'
    end

    # Locked users cannot access any resources
    if @user.locked || @user.removal_request_time
      $rest_log.error("[#{@request_id}] IDTokenGenerator::generate(): the user is locked or marked for deletion")
      return 'access_denied'
    end

    # Some handlers need the external data
    @external_data = {}

    if @user.external_data
      begin
        @external_data = JSON.parse(@user.external_data)
      rescue StandardError => e
        $rest_log.warn("[#{@request_id}] IDTokenGenerator::generate(): unable to parse user's external data: #{e}")
      end
    end

    user_data = {}

    @scopes = scopes
    @school_cache = {}
    @has_ldap = @scopes.include?('puavo.read.userinfo.ldap')

    # Handler functions for all possible scopes. Use lambdas when additional arguments are needed.
    scope_handlers = {
      'profile' => -> { handle_profile(include_sub) },
      'email' => method(:handle_email),
      'phone' => method(:handle_phone),
      'puavo.read.userinfo.primus' => method(:handle_primus),
      'puavo.read.userinfo.schools' => method(:handle_schools),
      'puavo.read.userinfo.groups' => method(:handle_groups),
      'puavo.read.userinfo.organisation' => method(:handle_organisation),
      'puavo.read.userinfo.admin' => method(:handle_admin),
      'puavo.read.userinfo.security' => method(:handle_security)
    }.freeze

    # Iterate over the scope handlers instead of scopes. This ensures the outputted claims are
    # always in a predetermined order, regardless of the scopes' order.
    scope_handlers.each do |scope, handler|
      next unless @scopes.include?(scope)

      begin
        result = handler.call
        user_data.merge!(result) if result
      rescue StandardError => e
        $rest_log.error("[#{@request_id}] Calling the handler for scope #{scope.inspect} failed: #{e}")
        @uschool_cache = nil
        return 'server_error'
      end
    end

    @uschool_cache = nil
    user_data
  end

  private

  # Standard claim: profile
  def handle_profile(include_sub)
    out = {}

    # Try to extract the modification timestamp from the LDAP operational attributes
    begin
      extra = User.raw_filter("ou=People,#{@organisation['base']}",
                              "(puavoId=#{@user.id})",
                              ['modifyTimestamp'])
      updated_at = Time.parse(extra[0]['modifyTimestamp'][0]).to_i
    rescue StandardError => e
      $rest_log.warn("[#{@request_id}] Cannot determine the user's last modification time: #{e}")
      updated_at = nil
    end

    # Standard claims
    out['sub'] = @user.uuid if include_sub
    out['given_name'] = @user.first_name
    out['family_name'] = @user.last_name
    out['name'] = "#{@user.first_name} #{@user.last_name}"
    out['preferred_username'] = @user.username
    out['updated_at'] = updated_at unless updated_at.nil?
    out['locale'] = @user.locale
    out['zoneinfo'] = @user.timezone

    # Puavo-specific claims
    out['puavo.uuid'] = @user.uuid
    out['puavo.puavoid'] = @user.puavo_id.to_i
    out['puavo.ldap_dn'] = @user.dn if @has_ldap
    out['puavo.external_id'] = @user.external_id if @user.external_id
    out['puavo.learner_id'] = @user.learner_id if @user.learner_id
    out['puavo.roles'] = @user.roles
    out['puavo.account_expiration_time'] = @user.account_expiration_time.to_i if @user.account_expiration_time

    out
  end

  # Standard claim: email
  def handle_email
    out = {}

    if @user.primary_email.nil?
      if @user.verified_email.empty?
        # Just pick the first available address
        if @user.email && !@user.email.empty?
          out['email'] = @user.email[0]
        else
          out['email'] = nil
        end

        out['email_verified'] = false
      else
        # This should not really happen, as the first verified email is
        # also the primary email
        out['email'] = @user.verified_email[0]
        out['email_verified'] = true
      end
    else
      # Prefer the primary email address if possible
      out['email'] = @user.primary_email
      out['email_verified'] =
        @user.verified_email &&
        @user.verified_email.include?(@user.primary_email)
    end

    out
  end

  # Standard claim: phone
  def handle_phone
    { 'phone_number' => @user.telephone_number[0] } unless @user.telephone_number.empty?
  end

  # Custom claim: puavo.read.userinfo.primus
  def handle_primus
    { 'puavo.primus_card_id' => @external_data.fetch('primus_card_id', nil) }
  end

  # Custom claim: puavo.read.userinfo.schools
  def handle_schools
    has_mpass = @scopes.include?('puavo.read.userinfo.mpassid')

    if has_mpass && @external_data.include?('materials_charge')
      # Parse MPASSid materials charge info
      mpass_charging_state, mpass_charging_school = @external_data['materials_charge'].split(';')
    end

    schools = @user.schools.collect do |s|
      @school_cache[s.dn] = s

      school = {
        'name' => s.name,
        'abbreviation' => s.abbreviation,
        'puavoid' => s.puavo_id.to_i,
        'external_id' => s.external_id,
        'school_code' => s.school_code,
        'oid' => s.school_oid,
        'primary' => @user.primary_school_dn == s.dn
      }

      if has_mpass && s.school_code == mpass_charging_school
        school['mpass_learning_materials_charge'] = mpass_charging_state
      end

      school['ldap_dn'] = s.dn if @has_ldap
      school
    end

    { 'puavo.schools' => schools }
  end

  # Custom claim: puavo.read.userinfo.groups
  def handle_groups
    have_schools = @scopes.include?('puavo.read.userinfo.schools')

    groups = @user.groups.collect do |g|
      group = {
        'name' => g.name,
        'abbreviation' => g.abbreviation,
        'puavoid' => g.id.to_i,
        'external_id' => g.external_id,
        'type' => g.type
      }

      group['ldap_dn'] = g.dn if @has_ldap

      if have_schools
        sch = get_school(g.school_dn)

        group['school_abbreviation'] = sch.abbreviation
        group['school_puavoid'] = sch.id.to_i
      end

      group
    end

    { 'puavo.groups' => groups }
  end

  # Custom claim: puavo.read.userinfo.admin
  def handle_admin
    {
      'puavo.is_organisation_owner' => @organisation.owner.include?(@user.dn),
      'puavo.admin_in_schools' => @user.admin_of_school_dns.collect { |dn| get_school(dn).abbreviation }
    }
  end

  # Custom claim: puavo.read.userinfo.organisation
  def handle_organisation
    org = {
      'name' => @organisation.name,
      'domain' => @organisation.domain
    }

    org['ldap_dn'] = @organisation.dn if @scopes.include?('puavo.read.userinfo.ldap')

    { 'puavo.organisation' => org }
  end

  # Custom claim: puavo.read.userinfo.security
  def handle_security
    {
      'puavo.mfa_enabled' => @user.mfa_enabled == true,
      'puavo.super_owner' => @organisation.owner.include?(@user.dn) && PuavoRest.super_owner?(@user.username)
    }
  end

  # School searches are slow, so cache them
  def get_school(school_dn)
    @school_cache[school_dn] = School.by_dn(school_dn) unless @school_cache.include?(school_dn)
    @school_cache[school_dn]
  end
end
end   # module OAuth2
end   # module PuavoRest
