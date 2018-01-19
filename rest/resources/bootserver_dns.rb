require 'open3'

module PuavoRest
  class BootserverDNS < PuavoSinatra
    Update_cmd = '/usr/local/lib/puavo-update-ddns'

    def check_parameter(params, sym)
      value = params[sym]
      if !value.kind_of?(String) || value.empty? then
        raise BadInput,
              :user => %Q("#{ sym }"-parameter is not given or a valid string)
      end

      return value
    end

    post '/v3/bootserver_dns_update' do
      # XXX what auth should be?  basic_auth plus we should restrict to
      # XXX a particular username?  or is that good?
      # XXX should be restricted to bootserver only, not to cloud!

      if not CONFIG['bootserver'] then
        status 404
        errmsg = 'This operation is supported only on bootservers.'
        return json({ :status => 'failed', :error => errmsg })
      end

      # The "puavo-update-ddns"-script is not a puavo-rest dependency,
      # so I suppose it is optional and we should check if the system supports
      # this feature.
      if !File.executable?(Update_cmd) then
        errmsg = "#{ Update_cmd } does not exist or is not executable"
        status 404
        return json({ :status => 'failed', :error => errmsg })
      end

      type       = check_parameter(params, :type)
      client_mac = check_parameter(params, :client_mac)
      client_ip  = check_parameter(params, :client_ip)
      subdomain  = check_parameter(params, :subdomain)

      cmd = [ Update_cmd, type, client_mac, client_ip, subdomain ]
      stdout_and_stderr_str, status = Open3.capture2e(*cmd)

      # XXX log both errors and successes

      if !status.success? then
        errmsg = "#{ Update_cmd } returned status code" \
                   + " #{ status.exitstatus } and error message:" \
                   + " '#{ stdout_and_stderr_str }'"
        raise InternalError, :user => errmsg
      end

      return 'ok'
    end
  end
end
