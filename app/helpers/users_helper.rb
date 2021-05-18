module UsersHelper
  include Puavo::Helpers

  def default_image_or_user_image_path(path, user)
    if user.jpegPhoto
      path
    else
      "anonymous.png"
    end
  end

  def self.convert_requested_user_column_names(requested)
    attributes = []

    attributes << 'puavoId' if requested.include?('id')
    attributes << 'sn' if requested.include?('last')
    attributes << 'givenName' if requested.include?('first')
    attributes << 'uid' if requested.include?('uid')
    attributes << 'puavoEduPersonAffiliation' if requested.include?('role')
    attributes << 'puavoExternalId' if requested.include?('eid')
    attributes << 'puavoExternalData' if requested.include?('learner_id')
    attributes << 'telephoneNumber' if requested.include?('phone')
    attributes << 'displayName' if requested.include?('name')
    attributes << 'homeDirectory' if requested.include?('home')
    attributes << 'mail' if requested.include?('email')
    attributes << 'puavoEduPersonPersonnelNumber' if requested.include?('pnumber')
    attributes << 'puavoRemovalRequestTime' if requested.include?('rrt')
    attributes << 'puavoDoNotDelete' if requested.include?('dnd')
    attributes << 'puavoLocked' if requested.include?('locked')
    attributes << 'createTimestamp' if requested.include?('created')
    attributes << 'modifyTimestamp' if requested.include?('modified')
    attributes << 'puavoSchool' if requested.include?('school')

    return attributes
  end

  def self.build_common_user_properties(user, requested)
    u = {}

    if requested.include?('first')
      u[:first] = user['givenName'] ? user['givenName'][0] : nil
    end

    if requested.include?('last')
      u[:last] = user['sn'] ? user['sn'][0] : nil
    end

    if requested.include?('eid')
      u[:eid] = user['puavoExternalId'] ? user['puavoExternalId'][0] : nil
    end

    if requested.include?('phone')
      u[:phone] = user['telephoneNumber'] ? Array(user['telephoneNumber']) : nil
    end

    if requested.include?('home')
      u[:home] = user['homeDirectory'][0]
    end

    if requested.include?('email')
      u[:email] = user['mail'] ? Array(user['mail']) : nil
    end

    if requested.include?('pnumber')
      u[:pnumber] = user['puavoEduPersonPersonnelNumber'] ? user['puavoEduPersonPersonnelNumber'][0] : nil
    end

    if requested.include?('created')
      u[:created] = Puavo::Helpers::convert_ldap_time(user['createTimestamp'])
    end

    if requested.include?('modified')
      u[:modified] = Puavo::Helpers::convert_ldap_time(user['modifyTimestamp'])
    end

    # Learner ID, if present. I wonder what kind of performance impact this
    # kind of repeated JSON parsing has?
    if requested.include?('learner_id') && user.include?('puavoExternalData')
      begin
        ed = JSON.parse(user['puavoExternalData'][0])
        if ed.include?('learner_id') && ed['learner_id']
          u[:learner_id] = ed['learner_id']
        end
      rescue
      end
    end

    return u
  end
end
