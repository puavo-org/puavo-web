# All servers-related mass operations

class ServersMassOperationsController < MassOperationsController
  include Puavo::CommonShared

  # POST '/servers_mass_operation'
  def servers_mass_operation
    prepare

    unless is_owner?
      return render json: { ok: false, message: t('supertable.mass.operation_not_permitted'), request_id: @request_id }
    end

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'set_field'
          # This comes from Puavo::CommonShared
          set_database_field(Server.find(id))

        when 'puavoconf_edit'
          # This comes from Puavo::CommonShared
          puavoconf_edit(Server.find(id))

        else
          next false, "Unknown operation \"#{@operation}\""
      end
    end

    render json: result
  rescue StandardError => e
    render json: { ok: false, message: e, request_id: @request_id }
  end
end
