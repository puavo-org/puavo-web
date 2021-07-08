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
      'homeDirectory',
      'mail',
      'puavoEduPersonPersonnelNumber',
      'puavoRemovalRequestTime',
      'puavoDoNotDelete',
      'puavoLocked',
      'createTimestamp',
      'modifyTimestamp',
      'puavoSchool',
    ].freeze
  end

  def self.convert_raw_user(dn, raw, organisation_owners, school_admins)
    out = {}

    out[:id] = raw['puavoId'][0].to_i

    out[:uid] = raw['uid'][0]

    out[:first] = raw['givenName'][0]

    out[:last] = raw['sn'][0]

    out[:name] = raw['displayName'][0]

    out[:role] = Array(raw['puavoEduPersonAffiliation'])
    out[:role].unshift('schooladmin') if school_admins.include?(dn)
    out[:role].unshift('owner') if organisation_owners.include?(dn)

    if raw['puavoRemovalRequestTime']
      out[:rrt] = Puavo::Helpers::convert_ldap_time(raw['puavoRemovalRequestTime'])
    end

    out[:dnd] = raw['puavoDoNotDelete'] ? true : false

    if raw['puavoLocked']
      out[:locked] = raw['puavoLocked'][0] == 'TRUE' ? true : false
    end

    if raw.include?('puavoExternalId')
      out[:eid] = raw['puavoExternalId'][0]
    end

    if raw.include?('telephoneNumber')
      a = Array(raw['telephoneNumber'])

      if a.count > 0
        out[:phone] = a
      end
    end

    if raw.include?('homeDirectory')
      out[:home] = raw['homeDirectory'][0]
    end

    if raw.include?('mail')
      a = Array(raw['mail'])

      if a.count > 0
        out[:email] = a
      end
    end

    if raw.include?('puavoEduPersonPersonnelNumber')
      out[:pnumber] = raw['puavoEduPersonPersonnelNumber'][0]
    end

    if raw.include?('createTimestamp')
      out[:created] = Puavo::Helpers::convert_ldap_time(raw['createTimestamp'])
    end

    if raw.include?('createTimestamp')
      out[:modified] = Puavo::Helpers::convert_ldap_time(raw['modifyTimestamp'])
    end

    # Learner ID, if present. I wonder what kind of performance impact this
    # kind of repeated JSON parsing has?
    if raw.include?('puavoExternalData')
      begin
        ed = JSON.parse(raw['puavoExternalData'][0])

        if ed.include?('learner_id') && ed['learner_id']
          out[:learner_id] = ed['learner_id']
        end
      rescue
      end
    end

    return out
  end
end
