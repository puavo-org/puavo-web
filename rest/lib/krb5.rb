module KRB5
  extend FFI::Library
  class ResultError < Exception
    attr_accessor :code, :method
    def initialize(data, *args)
      @code = data[:code]
      @method = data[:method]
      super(data[:message], *args)
    end
  end

  ffi_lib "libkrb5.so.3"

  # OM_uint32 krb5_init_context(krb5_context *context)
  attach_function :krb5_init_context, [:pointer], :OM_uint32

  # void krb5_free_context(krb5_context context)
  attach_function :krb5_free_context, [:pointer], :void

  # void krb5_free_principal( krb5_context context, krb5_principal principal)
  attach_function :krb5_free_principal, [:pointer, :pointer], :void


  # krb5_error_code krb5_cc_destroy( krb5_context context, krb5_ccache ccache)
  attach_function :krb5_cc_destroy, [:pointer, :pointer], :OM_uint32

  attach_function :krb5_parse_name, [:pointer, :pointer, :pointer], :OM_uint32

  attach_function :krb5_cc_resolve, [:pointer, :string, :pointer], :OM_uint32

  attach_function :krb5_cc_initialize, [:pointer, :pointer, :pointer], :OM_uint32

  attach_function :krb5_cc_get_principal, [:pointer, :pointer, :pointer], :OM_uint32

  attach_function :error_message, [:OM_uint32], :string

  def self.assert_call(method, *args)
    code = send(method, *args)
    if code.to_i != 0
      msg = error_message(code)
      raise ResultError, {
        :code => code,
        :method => method,
        :message => msg
      }
    end
    code
  end
end
