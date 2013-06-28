
require_relative "./krb5"
require "uuid"


class Krb5Gssapi

  class Error < Exception; end
  class NoDelegation < Error; end

  attr_accessor :return_token, :ok

  def initialize(fqdn, keytab)
    @srv = GSSAPI::Simple.new(fqdn, "HTTP", keytab)
    @cachename = "MEMORY:#{ UUID.generator.generate }"
  end

  def display_name
    @srv.display_name
  end

  def copy_ticket(input_token)
    @srv.acquire_credentials

    # TODO: https://github.com/zenchild/gssapi/blob/master/lib/gssapi/simple.rb#L102-L103
    otok = @srv.accept_context(input_token)
    if otok && otok != true
      @return_token = otok
    end

    if @srv.delegated_credentials.nil?
      raise NoDelegation
    end

    context = FFI::MemoryPointer.new :pointer # krb5_context
    principal = FFI::MemoryPointer.new :pointer # krb5_principal
    ccache = FFI::MemoryPointer.new :pointer   # krb5_ccache
    minor = FFI::MemoryPointer.new :OM_uint32

    KRB5::assert_call :krb5_init_context, context
    KRB5::assert_call :krb5_parse_name, context.get_pointer(0), display_name, principal
    KRB5::assert_call :krb5_cc_resolve, context.get_pointer(0), @cachename, ccache
    KRB5::assert_call :krb5_cc_initialize, context.get_pointer(0), ccache.get_pointer(0), principal.get_pointer(0)
    KRB5::assert_call :krb5_free_principal, context.get_pointer(0), principal.get_pointer(0)

    res = GSSAPI::LibGSSAPI::gss_krb5_copy_ccache(minor, @srv.delegated_credentials, ccache.get_pointer(0))

    ENV['KRB6CCNAME'] = @cachename
    @ok = true
  end

  def clean_up
    ENV.delete('KRB5CCNAME')
  end
end
