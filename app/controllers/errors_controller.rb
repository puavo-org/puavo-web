class ErrorsController < ApplicationController
  def unhandled_exception
    @error = env["action_dispatch.exception"]
    @error_uuid = (0...25).map{ ('a'..'z').to_a[rand(26)] }.join
    flog.error "unhandled exception", :error => {
      :uuid => @error_uuid,
      :class => @error.class.name,
      :message => @error.message,
      :backtrace => @error.backtrace
    }
    logger.error @error.message
    logger.error @error.backtrace.join("\n")
    render "sorry", :layout => false
  end
end
