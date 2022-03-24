# External inventory management integration

require 'digest'
require 'json'

module Puavo
  module Inventory
    def self.send_device_hardware_info(logger, config, device, hw_info)
      self.send_device_change(logger, config, 'device_hwinfo_update', {
        'id' => device.puavo_id.to_i,
        'hostname' => device.hostname,
        'domain' => device.organisation.domain,
        'type' => device.type,
        'school_id' => device.school.id.to_i,
        'school_dn' => device.school.dn,
        'school_name' => device.school.name,
        'hw_info' => hw_info.to_s
      })
    end

    def self.device_deleted(logger, config, id)
      self.send_device_change(logger, config, 'device_deleted', { "id" => id })
    end

    private

    def self.send_device_change(logger, config, command, params)
      uri = URI.parse(config['host'] + '/v0/devicechanges')
      http = Net::HTTP.new(uri.host, uri.port)
      post = Net::HTTP::Post.new(uri.request_uri)

      # Authorization key
      post.add_field(config['auth']['key'], Digest::SHA256.hexdigest(config['auth']['value']))

      post.body = {
        'command' => command,
        'params' => params
      }.to_json

      attempt = 1

      logger.info("Puavo::Inventory::send_device_change(): sending update command \"#{command}\" to \"#{uri.to_s}\"")

      begin
        response = http.request(post)
      rescue => e
        logger.error("Puavo::Inventory::send_device_change(): send failed: #{e}")

        # Retry five times to weed out intermittent network errors
        if attempt < 5
          logger.info("Puavo::Inventory::send_device_change(): attempt #{attempt + 1} in 1 second...")
          attempt += 1
          sleep 1
          retry
        else
          logger.error('Puavo::Inventory::send_device_change(): all attempts used, giving up')
          return
        end
      end
    end

  end
end
