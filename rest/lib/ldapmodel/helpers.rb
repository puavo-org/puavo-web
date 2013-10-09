class LdapModel

  def self.callable_from_instance(method)
    klass = self
    define_method method do |*args|
      klass.send(method, *args)
    end
  end

  # Create LdapModel from other hash. Converts attributes.
  def self.from_hash(hash)
    new.ldap_merge!(hash)
  end

  def self.is_dn(s)
    # Could be slightly better I think :)
    # but usernames should have no commas or equal signs
    s && s.include?(",") && s.include?("=")
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
  callable_from_instance :escape
end
