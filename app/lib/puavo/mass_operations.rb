# Used in mass operation controller endpoints to create return messages

module Puavo
  module MassOperations
    def status_ok
      render :json => { success: true, message: nil }
    end

    def status_failed_trans(code)
      render :json => { success: false, message: t(code) }
    end

    def status_failed_msg(message)
      render :json => { success: false, message: message.to_s }
    end
  end
end
