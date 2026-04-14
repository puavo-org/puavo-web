require 'securerandom'
require_relative "./krb5"

class Krb5Gssapi

  class Error < StandardError; end
  class NoDelegation < Error; end

  attr_accessor :return_token, :ok

  def initialize(fqdn, keytab)
    @srv = GSSAPI::Simple.new(fqdn, "HTTP", keytab)
  end

  def get_delegated_credentials(ticket)
    @srv.acquire_credentials

    otok = @srv.accept_context(ticket)
    if otok && otok != true
      @return_token = otok
    end

    raise NoDelegation unless @srv.delegated_credentials

    @ok = true
    @srv.delegated_credentials
  end

  def display_name
    @srv.display_name
  end
end
