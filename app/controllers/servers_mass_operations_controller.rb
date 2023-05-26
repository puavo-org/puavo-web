# All servers-related mass operations

class ServersMassOperationsController < MassOperationsController
  include Puavo::DevicesShared

  # POST '/servers_mass_operation'
  def servers_mass_operation
    prepare

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'set_field'
          set_database_field(Server.find(id), is_server: true)

        when 'puavoconf_edit'
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
