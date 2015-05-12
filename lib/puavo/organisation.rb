module Puavo

  class Organisation
    @@configurations = {}
    @@key_by_host = {}

    cattr_accessor :configurations, :key_by_host
    attr_accessor :organisation_key


    def locale
      @@configurations[organisation_key]["locale"] || :en
    end

    def schools(user)
      School.all_with_permissions user
    end

    def value_by_key(key)
      @@configurations[organisation_key][key]
    end

    def method_missing(method, *args)
      if @@configurations[organisation_key].has_key?(method.to_s)
        @@configurations[organisation_key][method.to_s]
      else
        super
      end
    end

    class << self

      def find(key)
        Organisation.initial_configurations if self.configurations.empty?

        if self.configurations.has_key?(key)
          organisation = Organisation.new
          organisation.organisation_key = key
          organisation
        else
          logger.info "Can not find configuration key: #{key}"
          false
        end
      end

      def key_by_host(host)
        Organisation.initial_configurations if self.configurations.empty?

        puts @@key_by_host.keys.inspect

        @@key_by_host[host]
      end

      def find_by_host(host)
        Organisation.initial_configurations if self.configurations.empty?

        if @@key_by_host.has_key?(host)
          organisation = Organisation.new
          organisation.organisation_key = @@key_by_host[host]
          organisation
        else
          logger.info "Can not find organisation by host: #{host}"
          false
        end
      end

      def all
        Organisation.initial_configurations if self.configurations.empty?

        @@configurations
      end

      def logger
        Rails.logger
      end

      def fetch_initial_configurations
        rest_response = HTTP.with_headers(:host => 'hogwarts.opinsys.net')
          .basic_auth(:user => PUAVO_ETC.ds_puavo_dn, :pass => PUAVO_ETC.ds_puavo_password)
          .get("#{ Puavo::CONFIG['puavo_rest']['host'] }/v3/organisations")

        case rest_response.status.to_s
        when /^2/
          initial_configurations = JSON.parse(rest_response.body) #FIXME readpartial
        else
          raise "Can't get organisations from puavo-rest! #{rest_response.status}"
        end
      end
      def initial_configurations=(organisations)
        organisations.each do |organisation|
          @@key_by_host[ organisation["domain"] ] = organisation["key"]

          web_config = organisation["web_config"] || Hash.new

          puts organisation["key"]
          puts organisation["domain"]
          @@configurations[organisation["key"]] = {
            "name" => organisation["name"],
            "host" => organisation["domain"],
            "ldap_host" => organisation["ldap_host"],
            "ldap_base" => organisation["base"],
            "locale" => web_config["locale"] || "en",
            "owner" => web_config["owner"] || "cucumber", # FIXME
            "owner_pw" => web_config["owner_pw"] || "cucumber" # FIXME
          }
        end
      end

    end

  end
end
