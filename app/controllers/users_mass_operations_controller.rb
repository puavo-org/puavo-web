# All users-related mass operations: delete, lock, mark for deletion, username lists, etc.

class UsersMassOperationsController < MassOperationsController
  include Puavo::Integrations
  include Puavo::UsersShared

  # POST '/users_mass_operation'
  def users_mass_operation
    prepare

    list_uids = []

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'delete'
          _delete(id, data)

        when 'lock'
          _lock(id, data)

        when 'mark_for_deletion'
          _mark_for_deletion(id, data)

        when 'clear_column'
          _clear_column(id, data)

        when 'create_username_list'
          begin
            User.find(id)
            list_uids << id
          rescue StandardError => e
            next false, "User ID #{id} not found: #{e}"
          end

        when 'change_school'
          _change_school(id, data)

        else
          next false, "Unknown operation \"#{@operation}\""

        next [true, nil]
      end
    end

    # TODO: Single-shot operations are fugly under this new system, but there's only
    # one of them, so I won't stress myself much with it yet.
    if @single_shot && @operation == 'create_username_list' && list_uids.count > 0
      creator = @parameters.fetch('creator', nil)
      description = @parameters.fetch('description', nil)
      new_list = List.new(list_uids, creator, description)
      new_list.save
    end

    render json: result
  rescue StandardError => e
    render json: { ok: false, message: e, request_id: @request_id }
  end

  private

  def _user_is_owner(user)
    Array(LdapOrganisation.current.owner).include?(user.dn)
  end

  # Mass operation: delete user
  def _delete(user_id, data)
    user = User.find(user_id)

    # Re-check the data. The client-side checks exist only to prevent easily avoidable
    # network traffic, but because they're run in the client, they cannot be fully
    # trusted. But we can trust these.
    if user.id == current_user.id
      return false, t('users.index.mass_operations.delete.cant_delete_yourself')
    end

    if Array(user.puavoEduPersonAffiliation).include?('admin') && _user_is_owner(user)
      return false, t('users.index.mass_operations.delete.cant_delete_owners')
    end

    if user.puavoDoNotDelete
      return false, t('users.index.mass_operations.delete.deletion_prevented')
    end

    unless user.puavoRemovalRequestTime
      return false, t('users.index.mass_operations.delete.not_marked_for_deletion')
    end

    if user.puavoRemovalRequestTime + 7.days > Time.now.utc
      return false, t('users.index.mass_operations.delete.marked_too_recently')
    end

    # Remove the user from external systems first, stop if this fails
    status, message = delete_user_from_external_systems(user, plaintext_message: true)
    return [false, message] unless status

    # LDAP is not a relational database, so if this user was the primary user of any devices,
    # we must manually break those connections.
    begin
      DevicesHelper.clear_device_primary_user(user.dn)
    rescue StandardError => e
      # At least one device failed, CANCEL the opeation to avoid dangling references
      logger.info("Failed to clear the primary user of a device: #{e}")
      return false, t('flash.device_primary_user_removal_failed')
    end

    user.destroy

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

  # Mass operation: lock/unlock user
  def _lock(user_id, data)
    user = User.find(user_id)
    lock = @parameters['lock']
    changed = false

    if Array(user.puavoEduPersonAffiliation).include?('admin') && _user_is_owner(user)
      return false, t('users.index.mass_operations.lock.cant_lock_owners')
    end

    if user.id == current_user.id
      return false, t('users.index.mass_operations.lock.cant_lock_yourself')
    end

    if user.puavoLocked && !lock
      user.puavoLocked = false
      changed = true
    elsif !user.puavoLocked && lock
      user.puavoLocked = true
      changed = true
    end

    user.save! if changed

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

  # Mass operation: mark/unmark for later deletion
  def _mark_for_deletion(user_id, data)
    user = User.find(user_id)
    changed = false

    if Array(user.puavoEduPersonAffiliation).include?('admin') && _user_is_owner(user)
      return false, t('users.index.mass_operations.mark.cant_mark_owners')
    end

    if user.id == current_user.id
      return false, t('users.index.mass_operations.mark.cant_mark_yourself')
    end

    case @parameters
      when 'mark'
        # Can't mark non-deletable user for deletion
        if user.puavoDoNotDelete
          return false, t('users.index.mass_operations.delete.deletion_prevented')
        end

        unless user.puavoRemovalRequestTime
          user.puavoRemovalRequestTime = Time.now.utc
          user.puavoLocked = true
          changed = true
        end

      when 'mark_force'
        if user.puavoDoNotDelete
          return false, t('users.index.mass_operations.delete.deletion_prevented')
        end

        # Force (reset timestamp)
        user.puavoRemovalRequestTime = Time.now.utc
        user.puavoLocked = true
        changed = true

      when 'unmark'
        # Any user can be unmarked, though
        if user.puavoRemovalRequestTime
          user.puavoRemovalRequestTime = nil
          changed = true
        end
    end

    user.save! if changed

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

  # Mass operation: clear column (their values must be unique, so setting them
  # to anything except empty is pointless)
  def _clear_column(user_id, data)
    user = User.find(user_id)
    changed = false

    case @parameters
      when 'eid'
        if user.puavoExternalID
          user.puavoExternalID = nil
          changed = true
        end

      when 'email'
        if user.mail
          user.mail = nil
          changed = true
        end

      when 'telephone'
        if user.telephoneNumber
          user.telephoneNumber = nil
          changed = true
        end

      when 'pnumber'
        if user.puavoEduPersonPersonnelNumber
          user.puavoEduPersonPersonnelNumber = nil
          changed = true
        end

      when 'notes'
        if user.puavoNotes
          user.puavoNotes = nil
          changed = true
        end

      else
        return [false, "unknown column \"#{column}\""]
    end

    user.save! if changed

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

  # Mass operation: change school(s)
  def _change_school(user_id, data)
    user = User.find(user_id)
    ok = false

    # Needed when removing the user from the old groups (see later)
    remove_groups_from = user.puavoEduPersonPrimarySchool.to_s

    case @parameters['action']
      # ---------------------------------------------------------------------------------------------
      # Move (change the primary school)

      when 'move'
        unless user.puavoEduPersonPrimarySchool == @parameters['school_dn']
          school = School.find(@parameters['school_id'])

          previous_dn = user.puavoEduPersonPrimarySchool
          previous_school = School.find(previous_dn)

          if Array(user.puavoSchool).include?(@parameters['school_dn'])
            user.puavoEduPersonPrimarySchool = @parameters['school_dn']

            unless @parameters['keep']
              schools = Array(user.puavoSchool).dup
              schools.delete(previous_dn)
              user.puavoSchool = (schools.count == 1) ? schools[0] : schools
            end
          else
            schools = Array(user.puavoSchool).dup
            schools << @parameters['school_dn']

            unless @parameters['keep']
              schools.delete(previous_dn)
            end

            user.puavoSchool = (schools.count == 1) ? schools[0] : schools
            user.puavoEduPersonPrimarySchool = @parameters['school_dn']
          end

          user.save!

          unless @parameters['keep']
            # Remove the user from the previous primary school
            begin
              LdapBase.ldap_modify_operation(previous_dn, :delete, [{ 'member' => [user.dn.to_s] }])
            rescue ActiveLdap::LdapError::NoSuchAttribute
            end

            begin
              LdapBase.ldap_modify_operation(previous_dn, :delete, [{ 'memberUid' => [user.uid.to_s] }])
            rescue ActiveLdap::LdapError::NoSuchAttribute
            end
          end
        end

        if @parameters['remove_prev']
          # Remove the user from the previous school's groups. Find the user object again
          # so it's fully updated.
          user = User.find(user_id)

          user.groups.each do |group|
            group.remove_user(user) if group.puavoSchool == remove_groups_from
          end
        end

      # ---------------------------------------------------------------------------------------------
      # Add to school

      when 'add'
        unless Array(user.puavoSchool).include?(@parameters['school_dn'])
          school = School.find(@parameters['school_id'])

          user.puavoSchool = Array(user.puavoSchool) + [@parameters['school_dn']]
          user.save!
        end

      # ---------------------------------------------------------------------------------------------
      # Remove from school

      when 'remove'
        if Array(user.puavoSchool).include?(@parameters['school_dn'])
          if user.puavoEduPersonPrimarySchool == @parameters['school_dn']
            # Users cannot be removed from their primary school. You have to move them
            # to another school first, then remove the old primary school.
            return [false, t('users.index.mass_operations.change_school.cant_remove_primary_school')]
          else
            school = School.find(@parameters['school_id'])
            Puavo::UsersShared::remove_user_from_school(user, school)
          end
        end
    end

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end
end
