require 'dnsruby'

module PuavoRest
  class BootserverDNS < PuavoSinatra
    DNS_server_ip   = '127.0.0.1'
    DNS_server_port = '553'

    def check_parameter(params, sym)
      value = params[sym]
      if !value.kind_of?(String) || value.empty? then
        raise BadInput,
              :user => %Q("#{ sym }"-parameter is not given or a valid string)
      end

      return value
    end

    def update_dns(client_fqdn, client_ip, domain, key_name, key_secret)
      resolver = Dnsruby::Resolver.new({ :nameserver => DNS_server_ip })
      resolver.port = DNS_server_port

      dns_message = Dnsruby::Message.new(client_fqdn, Dnsruby::Types.A)

      resolver.send_plain_message(dns_message)
      resolver.tsig = [ key_name, key_secret ]

      update = Dnsruby::Update.new(domain)
      update.delete(client_fqdn, 'A')
      update.add(client_fqdn, 'A', 60, client_ip)

      in_addr = "#{ client_ip.split('.').reverse.join('.') }.in-addr.arpa"

      update_reverse = Dnsruby::Update.new('10.in-addr.arpa')
      update_reverse.delete(in_addr)
      update_reverse.add(in_addr, 'PTR', 60, "#{ client_fqdn }.")

      resolver.send_message(update)
      resolver.send_message(update_reverse)
    end

    post '/v3/bootserver_dns_update' do
      auth :server_auth

      if not CONFIG['bootserver'] then
        status 404
        errmsg = 'This operation is supported only on bootservers.'
        return json({ :status => 'failed', :error => errmsg })
      end

      # The previous script interface supported both "mac" and "hostname",
      # but there appears to be no instance of calling the script with
      # type == "hostname", so we check that type == "mac".
      type = check_parameter(params, :type)
      if type != 'mac' then
        raise BadInput, :user => 'Only "mac"-type is currently supported.'
      end

      client_mac = check_parameter(params, :client_mac)
      client_ip  = check_parameter(params, :client_ip)
      key_name   = check_parameter(params, :key_name)
      key_secret = check_parameter(params, :key_secret)
      subdomain  = check_parameter(params, :subdomain)

      # We accept slightly irregular mac addresses,
      # because isc-dhcp-server might provide us with such.
      client_mac = client_mac.split(':') \
                             .map { |s| s.length == 1 ? "0#{s}" : s } \
                             .join(':')

      host = nil
      # Get Device or LtspServer
      begin
        host = Host.by_mac_address!(client_mac)
      rescue NotFound => e
        status 404
        errmsg = "No host found for mac address '#{ client_mac }'"
        return json({ :status => 'failed', :error => errmsg })
      end

      puavo_domain = Host.organisation.domain
      client_fqdn = "#{ host.hostname }.#{ subdomain }.#{ puavo_domain }"

      begin
        update_dns(client_fqdn, client_ip, puavo_domain, key_name, key_secret) \
          unless params[:dry_run]
      rescue StandardError => e
        errmsg = "Error when updating DNS for #{ client_fqdn }" \
                   + " / #{ client_ip } / #{ client_mac } : #{ e.message }"
        raise InternalError, errmsg
      end

      flog.info('updated DNS records for host',
                {
                  :fqdn => client_fqdn,
                  :ip   => client_ip,
                  :mac  => client_mac,
                })

      json({ :status => 'successfully', :client_fqdn => client_fqdn })
    end
  end
end
