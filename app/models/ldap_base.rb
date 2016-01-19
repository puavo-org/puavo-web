class LdapBase < ActiveLdap::Base
  include Puavo::Connection

  def ldap_modify_operation(type, attributes)
    self.class.ldap_modify_operation(self.dn, type, attributes)
  end

  def self.ldap_modify_operation(dn, type, attributes)
    ldif = ActiveLdap::LDIF.new
    record = ActiveLdap::LDIF::ModifyRecord.new(dn)
    ldif << record
    attributes.each do |attribute|
      record.add_operation(type, attribute.keys.first, [], attribute)
    end
    LdapBase.load(ldif.to_s)
  end

  def self.ensure_dn(o)
    if o.class == ActiveLdap::DistinguishedName
      o
    elsif o.class == String
      ActiveLdap::DistinguishedName.parse o
    else
      o.dn
    end
  end

  def <=>(other_object)
    self.displayName.to_s <=> other_object.displayName.to_s
  end

  # Because Activeldap includes Enumerable mixin to the Base class[1] it gets
  # the enumerable version of the as_json method from ActiveSupport[2]. Which
  # is not what we want. Our models are more Hash like objects than
  # Enumerables.
  #
  # So build proper Hash presentation here
  #
  # [1]: https://github.com/activeldap/activeldap/blob/3.2.2/lib/active_ldap/base.rb#L662
  # [2]: https://github.com/rails/rails/blob/v3.2.12/activesupport/lib/active_support/json/encoding.rb#L207
  def as_json(options = {})
    allowed_attributes = self.attributes
    allowed_attributes.delete_if do |attribute, value|
      !self.schema.attribute(attribute).syntax.human_readable?
    end

    method_values = { }
    # Create Hash by :methods name if :methods options is set.
    if options.has_key?(:methods)
      method_values = Array(options[:methods]).inject({ }) do |result, method|
        result.merge( { "#{method}" => self.send(method) } )
      end
      options.delete(:methods)
    end
    # Include method's values to the return value'
    method_values.empty? ? allowed_attributes :
      allowed_attributes.merge( method_values )
  end

  def to_json(options = {})
    as_json(options).to_json
  end

  def self.search_as_utf8(args)
    search_result = self.search(args)

    search_result.each do |entry|
      dn = entry[0]
      attributes = entry[1]

      attributes.each do |key, value|
        value.each do |v|
          v.force_encoding('utf-8') if v.class == String
        end
      end
    end
  end

  def self.words_search_and_sort_by_name(attributes, name_attribute_block, filter_block, words)
    words = Net::LDAP::Filter.escape( words )

    filter = "(&" + words.split(" ").map do |w|
      filter_block.call(w)
    end.join() + ")"

    search_as_utf8(
      :filter => filter,
      :scope => :one,
      :attributes => (["puavoId", "puavoSchool"] + attributes)
    ).select do |dn, v|
      not Array(v["puavoSchool"]).empty?
    end.map do |dn, v|
      { "id" => v["puavoId"].first,
        "school_id" => v["puavoSchool"].first.match(/^puavoId=([^,]+)/).to_a[1],
        "puavoSchool" => v["puavoSchool"].first,
        "name" => name_attribute_block.class == Proc ? name_attribute_block.call(v) : v[name_attribute_block].first
      }.merge( attributes.inject({}) { |result, a| result.merge(a => v[a]) } )
    end.sort{ |a,b| a['name'] <=> b['name'] }
  end

  def find_self
    self.find(self.dn)
  end

  def self.base
    if self.name == "LdapBase"
      super
    else
      self.prefix ? self.prefix + LdapBase.base : LdapBase.base
    end
  end

  def self.resize_image(image_path)
    img = Magick::Image.read(image_path).first
    img.format = "JPEG"
    img.resize_to_fit(image_size[:width], image_size[:height]).to_blob
  end

  # resize image hook
  def resize_image
    if self.image && !self.image.path.to_s.empty?
      self.jpegPhoto = self.class.resize_image(self.image.path)
    end
  end

end
