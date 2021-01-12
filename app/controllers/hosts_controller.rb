# Used by /usr/sbin/puavo-register to get a list of available device types.
# This probably should be in puavo-rest, but... it's not.

class HostsController < ApplicationController
  def types
    render :json => Host.types(params[:boottype], current_user)
  end
end
