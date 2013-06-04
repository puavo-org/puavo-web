require 'puavo/ldap'

module PuavoRest
class LdapModel
  attr_accessor :store

  class ModelError < Exception
  end

  class BadInput < ModelError
    def code
      400
    end
  end

  @@ldap2json = {}

  @@organisations_by_domain = nil
  def self.organisations_by_domain
    return @@organisations_by_domain if @@organisations_by_domain

    puavo_ldap = Puavo::Ldap.new(:base => "")
    organisation_bases = puavo_ldap.all_bases

    puavo_ldap.unbind

    organisations_by_domain = {}

    organisation_bases.each do |base|
      puavo_ldap = Puavo::Ldap.new(:base => base)

      if organisation_entry = puavo_ldap.organisation
        organisation = Puavo::Client::Base.new_by_ldap_entry( organisation_entry )
        if PUAVO_ETC.domain == organisation.domain
          organisations_by_domain["*"] = organisation.data
        end
        organisations_by_domain[organisation.domain] = organisation.data
      end

      puavo_ldap.unbind
    end

    @@organisations_by_domain = organisations_by_domain
  end

  def initialize(ldap_conn, organisation_info)
    @ldap_conn = ldap_conn
    @organisation_info = organisation_info
  end

  # http://tools.ietf.org/html/rfc4515 lists these exceptions from UTF1
  # charset for filters. All of the following must be escaped in any normal
  # string using a single backslash ('\') as escape.
  #
  ESCAPES = {
    "\0" => '00', # NUL            = %x00 ; null character
    '*'  => '2A', # ASTERISK       = %x2A ; asterisk ("*")
    '('  => '28', # LPARENS        = %x28 ; left parenthesis ("(")
    ')'  => '29', # RPARENS        = %x29 ; right parenthesis (")")
    '\\' => '5C', # ESC            = %x5C ; esc (or backslash) ("\")
  }
  # Compiled character class regexp using the keys from the above hash.
  ESCAPE_RE = Regexp.new(
    "[" +
    ESCAPES.keys.map { |e| Regexp.escape(e) }.join +
    "]"
  )

  # Escape unsafe user input for safe LDAP filter use
  #
  # @see https://github.com/ruby-ldap/ruby-net-ldap/blob/8ddb2d7c8476c3a2b2ad9fcd367ca0d36edaa611/lib/net/ldap/filter.rb#L247-L264
  def self.escape(string)
    string.gsub(ESCAPE_RE) { |char| "\\" + ESCAPES[char] }
  end

  # Define conversion between LDAP attribute and the JSON attribute
  # @param ldap_name [Symbol] LDAP attribute to convert
  # @param json_name [Symbol] Value conversion block. Default: Get first array item
  # @param convert [Block] Use block to
  # @see convert
  def self.ldap_attr_conversion(ldap_name, json_name, &convert)
    hash = @@ldap2json[self.name] ||= {}
    hash[ldap_name.to_s] = {
      :attr => json_name.to_s,
      :convert => convert || lambda { |v| Array(v).first }
    }
  end

  # Return LDAP attributes that will be converted
  def self.ldap_attrs
    @@ldap2json[self.name].keys
  end

  # Covert LDAP entry Hash to JSON style Hash
  # @param entry [Hash] Ruby Hash from #filter
  # @param all [Boolean] Include also those attributes that have no attribute
  # conversion
  # @see ldap_attr_conversion
  # @see #filter
  def self.convert(entry, all=false)
    return nil if entry.nil?

    h = {}

    entry.each do |k,v|
      if ob = @@ldap2json[self.name][k.to_s]
        h[ob[:attr]] = ob[:convert].call(v)
      elsif all
        h[k] = v
      end
    end

    return h
  end

  # LDAP base for this model. Must be implemented by subclasses
  def ldap_base
    raise "not implemented"
  end

  # LDAP::LDAP_SCOPE_SUBTREE filter search for #ldap_base
  # @param filter [String] LDAP filter
  # @param attributes [Array] Limit search results to these attributes
  # @see #ldap_base
  # @see http://ruby-ldap.sourceforge.net/rdoc/classes/LDAP/Conn.html#M000025
  def filter(filter, attributes=nil)
    res = []

    @ldap_conn.search(
      ldap_base,
      LDAP::LDAP_SCOPE_SUBTREE,
      filter,
      attributes
    ) do |entry|
      res.push(entry.to_hash)
    end

    res
  end

  # Find any ldap entry by dn
  #
  # @param dn [String]
  # @param attributes [Array of Strings]
  def _find_by_dn(dn, attributes=[])
    res = nil

    @ldap_conn.search(
      dn,
      LDAP::LDAP_SCOPE_SUBTREE,
      "(objectclass=*)",
      attributes
    ) do |entry|
      res = entry.to_hash
      break
    end

    res
  end

end
end
