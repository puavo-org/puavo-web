module GroupsHelper
  include Puavo::Helpers

  def self.convert_requested_group_column_names(requested)
    # Given that out of the eight possible attributes, four are required,
    # it's easier to just fetch them all. We don't even touch the
    # 'requested' argument.
    return [
      'puavoId',
      'displayName',
      'cn',
      'puavoEduGroupType',
      'puavoExternalId',
      'memberUid',
      'puavoSchool',
      'createTimestamp',    # LDAP operational attribute
      'modifyTimestamp',    # LDAP operational attribute
    ].freeze
  end

  def self.build_common_group_properties(group, requested)
    return {
      id: group['puavoId'][0].to_i,
      name: group['displayName'][0],
      type: group['puavoEduGroupType'] ? group['puavoEduGroupType'][0] : nil,
      abbr: group['cn'][0],
      eid: group['puavoExternalId'] ? group['puavoExternalId'][0] : nil,
      members: group['memberUid'] ? group['memberUid'].count : 0,
      created: Puavo::Helpers::convert_ldap_time(group['createTimestamp']),
      modified: Puavo::Helpers::convert_ldap_time(group['modifyTimestamp'])
    }
  end
end
