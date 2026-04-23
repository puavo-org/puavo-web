# frozen_string_literal: true

module UsersHelper
  include Puavo::Helpers

  def default_image_or_user_image_path(path, user)
    if user.jpegPhoto
      path
    else
      'anonymous.png'
    end
  end

  # Returns the attributes used in raw queries on users list pages
  def self.users_raw_query_attributes
    %w[
      authTimestamp
      createTimestamp
      displayName
      givenName
      mail
      modifyTimestamp
      puavoDoNotDelete
      puavoEduPersonAccountExpirationTime
      puavoEduPersonAffiliation
      puavoEduPersonPersonnelNumber
      puavoEduPersonPrimarySchool
      puavoExternalData
      puavoExternalId
      puavoId
      puavoLearnerId
      puavoLicenses
      puavoLocked
      puavoMFAEnabled
      puavoNotes
      puavoPrimaryEmail
      puavoRemovalRequestTime
      puavoSchool
      puavoUuid
      puavoVerifiedEmail
      sn
      telephoneNumber
      uid
    ].freeze
  end
end
