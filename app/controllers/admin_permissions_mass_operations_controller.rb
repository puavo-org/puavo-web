# Organisation admin permissions mass operations controller

class AdminPermissionsMassOperationsController < MassOperationsController
  include Puavo::Integrations
  include Puavo::UsersShared

  # POST '/users_mass_operation'
  def admin_permissions_mass_operation
    prepare

    unless is_owner?
      return render json: { ok: false, message: t('supertable.mass.operation_not_permitted'), request_id: @request_id }
    end

    list_uids = []

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'grant_permissions'
          _grant_permissions(id, data)

        when 'revoke_permissions'
          _revoke_permissions(id, data)

        when 'set_permissions'
          _set_permissions(id, data)

        else
          next false, "Unknown operation \"#{@operation}\""

        next [true, nil]
      end
    end

    render json: result
  rescue StandardError => e
    render json: { ok: false, message: e, request_id: @request_id }
  end

  private

  def _grant_permissions(user_id, data)
    u = User.find(user_id)

    permissions = Array(u.puavoAdminPermissions || [])
    permissions += @parameters['permissions']
    permissions.uniq!
    u.puavoAdminPermissions = permissions
    u.save!

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

  def _revoke_permissions(user_id, data)
    u = User.find(user_id)

    permissions = Array(u.puavoAdminPermissions || [])
    permissions -= @parameters['permissions']
    permissions.uniq!
    u.puavoAdminPermissions = permissions
    u.save!

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

  def _set_permissions(user_id, data)
    u = User.find(user_id)
    u.puavoAdminPermissions = @parameters['permissions']
    u.save!

    return [true, nil]
  rescue StandardError => e
    return [false, e]
  end

end
