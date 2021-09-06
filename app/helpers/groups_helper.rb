module GroupsHelper
  include Puavo::Helpers

  def self.get_group_attributes()
    return [
      'puavoId',
      'displayName',
      'cn',
      'puavoEduGroupType',
      'puavoExternalId',
      'memberUid',          # for listing the members count
      'puavoSchool',
      'createTimestamp',    # LDAP operational attribute
      'modifyTimestamp',    # LDAP operational attribute
    ].freeze
  end

  def self.convert_raw_group(dn, raw)
    out = {}

    out[:id] = raw['puavoId'][0].to_i

    out[:name] = raw['displayName'][0]

    out[:abbr] = raw['cn'][0]

    if raw.include?('puavoEduGroupType') && raw['puavoEduGroupType']
      out[:type] = raw['puavoEduGroupType'][0]
    end

    if raw.include?('puavoExternalId')
      out[:eid] = raw['puavoExternalId'][0]
    end

    # This is just a plain number field, always include it
    out[:members_count] = raw.include?('memberUid') ? raw['memberUid'].count : 0

    if raw.include?('createTimestamp')
      out[:created] = Puavo::Helpers::convert_ldap_time(raw['createTimestamp'])
    end

    if raw.include?('modifyTimestamp')
      out[:modified] = Puavo::Helpers::convert_ldap_time(raw['modifyTimestamp'])
    end

    return out
  end
end
