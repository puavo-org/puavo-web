module UsersHelper
  include Puavo::Helpers

  def default_image_or_user_image_path(path, user)
    if user.jpegPhoto
      path
    else
      "anonymous.png"
    end
  end

  def self.get_user_attributes()
    # Which attributes to query? We could get *everything* with ["*"], but it would also
    # return attributes like jpegPhoto which are useless for us (we're NOT transferring
    # profile pictures here!).
    return [
      'puavoId',
      'sn',
      'givenName',
      'uid',
      'puavoEduPersonAffiliation',
      'puavoExternalId',
      'puavoExternalData',
      'telephoneNumber',
      'displayName',
      'mail',
      'puavoVerifiedEmail',
      'puavoPrimaryEmail',
      'puavoEduPersonPersonnelNumber',
      'puavoRemovalRequestTime',
      'puavoDoNotDelete',
      'puavoLocked',
      'createTimestamp',
      'modifyTimestamp',
      'authTimestamp',
      'puavoSchool',
      'puavoEduPersonPrimarySchool',
      'puavoLearnerId',
      'puavoLicenses',
      'puavoUuid',
      'puavoMFAEnabled',
      'puavoNotes',
    ].freeze
  end

  def self.convert_raw_user(dn, raw, organisation_owners, school_admins)
    out = {}

    out[:id] = raw['puavoId'][0].to_i

    out[:uuid] = raw.fetch('puavoUuid', [nil])[0]

    out[:uid] = raw['uid'][0]

    out[:first] = raw['givenName'][0]

    out[:last] = raw['sn'][0]

    out[:name] = raw['displayName'][0]

    out[:role] = Array(raw['puavoEduPersonAffiliation'])
    out[:role].unshift('schooladmin') if school_admins.include?(dn)
    out[:role].unshift('owner') if organisation_owners.include?(dn)

    if raw['puavoLearnerId']
      out[:learner_id] = raw['puavoLearnerId'][0]
    end

    if raw['puavoRemovalRequestTime']
      out[:rrt] = Puavo::Helpers::convert_ldap_time(raw['puavoRemovalRequestTime'])
    end

    if raw['puavoDoNotDelete']
      out[:dnd] = raw['puavoDoNotDelete'][0] == 'TRUE' ? true : false
    end

    if raw['puavoLocked']
      out[:locked] = raw['puavoLocked'][0] == 'TRUE' ? true : false
    end

    if raw.include?('puavoExternalId')
      out[:eid] = raw['puavoExternalId'][0]
    end

    if raw['puavoNotes']
      out[:notes] = raw['puavoNotes'][0]
    end

    if raw.include?('telephoneNumber')
      a = Array(raw['telephoneNumber'])

      if a.count > 0
        out[:phone] = a
      end
    end

    if raw.include?('mail')
      a = Array(raw['mail'])

      if a.count > 0
        out[:email] = a
      end
    end

    if raw.include?('puavoVerifiedEmail')
      a = Array(raw['puavoVerifiedEmail'])
      out[:v_email] = a if a.count > 0
    end

    if raw.include?('puavoPrimaryEmail')
      out[:p_email] = raw['puavoPrimaryEmail'][0]
    end

    if raw.include?('puavoEduPersonPersonnelNumber')
      out[:pnumber] = raw['puavoEduPersonPersonnelNumber'][0]
    end

    if raw.include?('authTimestamp')
      out[:last_ldap_auth_date] = Puavo::Helpers::convert_ldap_time_pick_date(raw['authTimestamp'])
    end

    if raw.include?('createTimestamp')
      out[:created] = Puavo::Helpers::convert_ldap_time(raw['createTimestamp'])
    end

    if raw.include?('modifyTimestamp')
      out[:modified] = Puavo::Helpers::convert_ldap_time(raw['modifyTimestamp'])
    end

    if raw.include?('puavoLicenses')
      begin
        licenses = JSON.parse(raw['puavoLicenses'][0])
        out[:licenses] = licenses.keys.sort
      rescue StandardError => e
      end
    end

    out[:mfa] = raw.include?('puavoMFAEnabled') && raw['puavoMFAEnabled'][0] == 'TRUE'

    return out
  end
end
