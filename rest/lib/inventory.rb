# External inventory management integration

require 'digest'
require 'json'

module Puavo
  module Inventory
    def self.send_device_hardware_info(logger, config, device, hw_info)
      self.send_device_change(logger, config, 'device_hwinfo_update',
         ( inventory_notification_from_device(device)
           .merge( { 'hw_info' => hw_info.to_s } ) ) )
    end

    def self.device_created(logger, config, device, organisation)
      self.send_device_change(logger, config, 'device_created',
           inventory_notification_from_device(device, organisation) )
    end

    def self.device_modified(logger, config, device, organisation)
      self.send_device_change(logger, config, 'device_modified',
           inventory_notification_from_device(device, organisation) )
    end

    def self.device_deleted(logger, config, id)
      self.send_device_change(logger, config, 'device_deleted', { "id" => id })
    end


    private

     def self.inventory_notification_from_device device, organisation=nil
       { # some requests come from rest and some from web, so we'll try to handle both formats
         'id' => device.puavo_id.to_i,
         'hostname' => (device.respond_to?(:hostname) ? device.hostname : device.puavoHostname),
         'domain' => organisation || device.organisation.domain,
         'type' => (device.respond_to?(:type) ? device.type : device.puavoDeviceType),
         'school_id' => (device.respond_to?(:school) ? device.school.id.to_i : device.school_id.to_i),
         'school_dn' => (device.school.dn if device.respond_to?(:school)),
         'school_name' => (device.school.name if device.respond_to?(:school)),
         'serial' => (device.respond_to?(:serial) ? device.serial : device.serial_number),
       }
     end

    def self.send_device_change(logger, config, command, params)
      uri = URI.parse(config['host'] + '/v0/devicechanges')

      http = Net::HTTP.new(uri.host, uri.port)

      # Ruby for the love of... why can't you figure this out yourself?
      http.use_ssl = true if uri.instance_of?(URI::HTTPS)

      post = Net::HTTP::Post.new(uri.request_uri)

      # This isn't a form submission
      post.add_field('Content-Type', 'application/json')

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
        logger.info("Puavo::Inventory::send_device_change(): response status: #{response.code}")
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
