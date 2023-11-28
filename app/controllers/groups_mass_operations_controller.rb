# All groups-related mass operations

class GroupsMassOperationsController < MassOperationsController
  include Puavo::GroupsShared

  # POST '/groups_mass_operation'
  def groups_mass_operation
    prepare

    group_cache = {}

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'set_type'
          Puavo::GroupsShared::set_type(Group.find(id), @parameters['type'])
          next [true, nil]

        when 'remove_members'
          Puavo::GroupsShared::remove_all_members(Group.find(id))
          next [true, nil]

        when 'lock_members'
          Puavo::GroupsShared::lock_members(Group.find(id), true)
          next [true, nil]

        when 'unlock_members'
          Puavo::GroupsShared::lock_members(Group.find(id), false)
          next [true, nil]

        when 'mark_members'
          Puavo::GroupsShared::mark_members_for_deletion(Group.find(id), true)
          next [true, nil]

        when 'unmark_members'
          Puavo::GroupsShared::mark_members_for_deletion(Group.find(id), false)
          next [true, nil]

        when 'delete'
          group = Group.find(id)
          group.destroy
          next [true, nil]

        when 'add_to_group'
          user = User.find(id)

          # Cache the groups
          @parameters['groups'].each do |gid|
            group_cache[gid] ||= Group.find(gid)
            group_cache[gid].add_user(user)
          end

          next [true, nil]

        when 'remove_from_group'
          user = User.find(id)

          # Cache the groups
          @parameters['groups'].each do |gid|
            group_cache[gid] ||= Group.find(gid)
            group_cache[gid].remove_user(user)
          end

          next [true, nil]

        else
          next false, "Unknown operation \"#{@operation}\""
      end
    end

    render json: result
  rescue StandardError => e
    render json: { ok: false, message: e, request_id: @request_id }
  end
end
