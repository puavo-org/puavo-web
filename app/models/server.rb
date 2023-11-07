require 'digest'
require 'base64'

class Server < DeviceBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Servers,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient', 'puavoServer', 'simpleSecurityObject'] )

  has_many( :automounts, :class_name => 'Automount',
            :primary_key => 'dn',
            :foreign_key => 'puavoServer' )

  def forced_schools
    out = []

    Array(puavoSchool).each do |school_dn|
      # you can't just plow ahead without any error checking!
      begin
        out << [true, School.find(school_dn)]
      rescue
        out << [false, school_dn.to_s]
      end
    end

    out
  end

  def self.ssha_hash(password)
    salt = SecureRandom.base64(16)
    "{SSHA}" + Base64.encode64(Digest::SHA1.digest(password + salt) + salt).chomp!
  end

  def full_hostname
    "#{self.puavoHostname}.#{LdapOrganisation.first.puavoDomain}"
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  # Special version of the base method, ignores schools completely
  def self.words_search_and_sort_by_name(attributes, name_attribute_block, filter_block, words)
    words = Net::LDAP::Filter.escape( words )

    filter = "(&" + words.split(" ").map do |w|
      filter_block.call(w)
    end.join() + ")"

    search_as_utf8(
      :filter => filter,
      :scope => :one,
      :attributes => (["puavoId"] + attributes)
    ).map do |dn, v|
      { "id" => v["puavoId"].first,
        "name" => name_attribute_block.class == Proc ? name_attribute_block.call(v) : v[name_attribute_block].first
      }.merge( attributes.inject({}) { |result, a| result.merge(a => v[a]) } )
    end.sort{ |a,b| a['name'] <=> b['name'] }
  end
end
