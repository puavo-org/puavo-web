require "jwt"
require "addressable/uri"
require 'securerandom'

module PuavoRest

class ExternalService < LdapModel
  ldap_map(:dn, :dn){ |dn| Array(dn).first.downcase.strip }
  ldap_map :cn, :name
  ldap_map :puavoServiceDomain, :domain, LdapConverters::ArrayValue
  ldap_map :puavoServiceSecret, :secret
  ldap_map :description, :description
  ldap_map :puavoServiceDescriptionURL, :description_url
  ldap_map :puavoServiceTrusted, :trusted, LdapConverters::StringBoolean
  ldap_map :puavoServicePathPrefix, :prefix, :default => "/"

  def self.ldap_base
    "ou=Services,o=puavo"
  end

  def self.by_domain(domain)
    by_attr(:domain, domain, :multiple => true)
  end

  def self.by_url(url)
    url = Addressable::URI.parse(url.to_s)

    return LdapModel.setup(:credentials => CONFIG["server"]) do
      # Single domain might have multiple external services configured to
      # different paths. Match paths from the longest to shortest.
      ExternalService.by_domain(url.host).sort do |a,b|
        b["prefix"].size <=> a["prefix"].size
      end.select do |s|
        if url.path.to_s.empty?
          path = "/"
        else
          path = url.path
        end
        path.start_with?(s["prefix"])
      end.first
    end
  end

  # Filters a User.to_hash down to a suitable level for SSO URLs
  def filtered_user_hash(user, request_username, request_domain)
    schools_hash = user.schools_hash()    # Does not call json()

    primary_school_id = user.primary_school_id

    # Remove everything that isn't the user's primary school. It would be nice
    # to include all schools in the hash, but URLs have maximum lengths and if
    # you have too many schools and groups in it, systems will start rejecting
    # it and logins will fail.
    schools_hash.delete_if{ |s| s["id"] != primary_school_id }

    # Remove DNs, they only take up space and aren't on the spec anyway
    schools_hash.each do |s|
      s.delete('dn')

      s['groups'].each do |g|
        g.delete('dn')
      end

      s['groups'].delete_if { |g| g['type'] == 'course group' }
    end

    year_class = user.year_class

    if year_class
      yc_name = year_class.name
    else
      yc_name = nil
    end

    # Build the output hash manually, without calling user.to_hash().
    # Include only the members that are on the spec (plus a few more).
    data = {
      'id' => user.id,
      'puavo_id' => user.puavo_id,
      'external_id' => user.external_id,
      'preferred_language' => user.preferred_language,
      'user_type' => user.user_type,    # unknown if actually needed
      'username' => user.username,
      'first_name' => user.first_name,
      'last_name' => user.last_name,
      'email' => Array(user.email || []).first,
      'primary_school_id' => primary_school_id,
      'year_class' => yc_name,
      'organisation_name' => user.organisation_name,
      'organisation_domain' => user.organisation_domain,
      'external_domain_username' => user.external_domain_username(request_username, request_domain),
      'schools' => schools_hash,
      'learner_id' => user.learner_id,
    }

    data
  end

  def generate_login_url(user_hash, return_to_url)
    return_to_url = Addressable::URI.parse(return_to_url.to_s)

    jwt_data = user_hash.merge({
      # Issued At
      "iat" => Time.now.to_i,
      # JWT ID
      "jti" => SecureRandom.uuid,
      "external_service_path_prefix" => prefix
    })

    jwt = JWT.encode(jwt_data, secret)
    return_to_url.query_values = (return_to_url.query_values || {}).merge("jwt" => jwt)
    return return_to_url.to_s, user_hash
  end
end

end
