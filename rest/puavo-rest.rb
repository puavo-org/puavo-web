require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "gssapi"
require "gssapi/lib_gssapi"
require "pry"
require "redis-namespace"
require "redlock"

require_relative "./lib/ldap_converters"
require_relative "./lib/helpers"
require_relative "./lib/logger"
require_relative "./lib/ldapmodel"
require_relative "./lib/hash_helpers"
require_relative "./middleware/suppress_json_errors"
require_relative "./middleware/virtual_host_base"

require_relative "./config"
require_relative "./lib/puavo_sinatra"
require_relative "./resources/id_pool"
require_relative "./resources/users"
require_relative "./resources/groups"
require_relative "./resources/samba_groups"
require_relative "./resources/samba_domains"
require_relative "./resources/schools"
require_relative "./resources/organisations"
require_relative "./resources/printer_queues"
require_relative "./resources/external_service"
require_relative "./resources/sso"
require_relative "./resources/sessions"
require_relative "./resources/wlan_networks"
require_relative "./resources/external_files"
require_relative "./resources/devices"
require_relative "./resources/boot_servers"
require_relative "./resources/boot_configurations"
require_relative "./resources/hosts"
require_relative "./resources/device_images"
require_relative "./resources/password"
require_relative "./resources/user_lists"
require_relative "./resources/certs"
require_relative "./resources/authentication"
require_relative "./resources/external_login"
require_relative "./resources/bootserver_dns"
require_relative "./resources/my_school_users"

if CONFIG["eltern_sso"]
require_relative "./resources/eltern"
end

REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys
DISTRIBUTED_LOCK = Redlock::Client.new([REDIS_CONNECTION])

PUAVO_SSO_SESSION_KEY = '_puavo_sso_session'.freeze
PUAVO_SSO_SESSION_LENGTH = (60 * 60 * 8).freeze       # 8 hours
