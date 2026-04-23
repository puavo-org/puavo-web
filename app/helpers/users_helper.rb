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
      'puavoEduPersonAccountExpirationTime',
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
end
