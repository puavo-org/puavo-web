module GroupsHelper
  include Puavo::Helpers

  def self.get_group_attributes()
    return [
      'puavoId',
      'displayName',
      'cn',
      'puavoEduGroupType',
      'puavoExternalId',
      'puavoNotes',
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

    if raw.include?('puavoNotes')
      out[:notes] = raw['puavoNotes'][0].gsub("\r", '').split("\n")
    end

    # This is just a plain number field, always include it
    out[:members_count] = raw.include?('memberUid') ? raw['memberUid'].count : 0

    if raw.include?('createTimestamp')
      out[:created] = Puavo::Helpers.ldap_time_string_to_unixtime(raw['createTimestamp'])
    end

    if raw.include?('modifyTimestamp')
      out[:modified] = Puavo::Helpers.ldap_time_string_to_unixtime(raw['modifyTimestamp'])
    end

    return out
  end

  # Generates the raw groups for users list pages
  def self.load_group_member_lists(schools_by_dn, accessible_schools)
    groups = {}
    group_members = {}

    # First do a raw search for all groups
    raw_groups = Group.search_as_utf8(
      filter: "(puavoSchool=*)",
      scope: :one,
      attributes: ['puavoId', 'displayName', 'puavoEduGroupType', 'puavoSchool', 'member']
    )

    # Then convert them into a more suitable format
    raw_groups.each do |dn, raw_group|
      school = schools_by_dn.fetch(raw_group['puavoSchool'][0], nil)

      unless accessible_schools.empty? || accessible_schools.include?(raw_group['puavoSchool'][0])
        # The current user is not an owner and they cannot access this school,
        # so don't link to it
        school = nil
      end

      members = raw_group.fetch('member', [])
      next if members.empty?

      id = raw_group['puavoId'][0].to_i

      groups[id] = {
        'name' => raw_group['displayName'][0],
        'type' => raw_group.fetch('puavoEduGroupType', [nil])[0],
        'link' => school.nil? ? nil : "/users/#{school[:id]}/groups/#{id}"
      }

      group_members[id] = members
    end

    return groups, group_members
  end
end
