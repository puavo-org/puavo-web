# All schools-related mass operations

class SchoolsMassOperationsController < MassOperationsController
  include Puavo::CommonShared

  # POST '/schools_mass_operation'
  def schools_mass_operation
    prepare

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'set_field'
          # This comes from Puavo::CommonShared
          set_database_field(School.find(id))

        when 'puavoconf_edit'
          # This comes from Puavo::CommonShared
          puavoconf_edit(School.find(id))

        else
          next false, "Unknown operation \"#{@operation}\""
      end
    end

    render json: result
  rescue StandardError => e
    render json: { ok: false, message: e, request_id: @request_id }
  end

  private
end
