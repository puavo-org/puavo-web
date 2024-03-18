class LdapModel
  def self.from_ldap_hash(ldap_attrs, serialize_attrs=nil)
    new({}, :serialize => serialize_attrs, :existing => true).ldap_merge!(ldap_attrs)
  end

  def self.is_dn(s)
    # Could be slightly better I think :)
    # but usernames should have no commas or equal signs
    s && s.include?(",") && s.include?("=")
  end

  # Shorter-to-type wrapper around Net::LDAP::Filter.escape
  def self.ldap_escape(string)
    Net::LDAP::Filter.escape(string.to_s)
  end
end


# ---------------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------------
# EXPERIMENTAL V4 API HELPER STUFF

# Use at your own risk


# custom exceptions, for common error handling for all operations
# I do not comprehend the fetish language designers have for using letter cases for deciding
# what "type" the name is. Why don't you just let me designate it with "public" or "internal"
# or "const" or something similar?
class V4_MissingFields < StandardError; end
class V4_UnknownField < StandardError; end
class V4_MissingParameter < StandardError; end
class V4_InvalidParameter < StandardError; end
class V4_DuplicateParameter < StandardError; end

# Known filter operators
OPERATORS = Set.new(['starts', 'ends', 'contains', 'is']).freeze

# Known fields that can accept multiple values
PERMIT_MULTIPLE = Set.new(['id']).freeze

# Attempts to detect if the user is high-level enough for this request
def v4_is_request_allowed?(current)
  return true if current && current.admin?
  return true if current && current.server_user?

  # uid=<name>,ou=System Accounts,dc=...
  if /^uid=[a-zA-Z0-9_\-]+,ou=System Accounts,dc=edu,dc=/.match(LdapModel.settings[:credentials][:dn])
    return true
  end

  # uid=<xxxxx>,o=puavo "super accounts" (they're dangerous but valid accounts, and the
  # rest of the authentication code lets them through, so they must be accepted here too)
  if /^uid=[a-z][a-z\-]+,o=puavo$/.match(LdapModel.settings[:credentials][:dn])
    return true
  end

  # Fail safe
  return false
end

def v4_get_fields(params)
  # Make sure there is a non-empty 'fields' parameter
  raise V4_MissingFields unless params.include?('fields')
  raise V4_MissingFields if params['fields'].nil? || params['fields'].empty?
  return params['fields'].split(',')
end

def v4_get_filters_from_params(params, user_to_ldap, base_class = '*')
  out = []
  puavoid = []

  Array(params.fetch('filter', nil) || []).each do |f|
    parts = f.split('|')

    # Silently ignore invalid filters
    next unless parts.count == 3
    next unless OPERATORS.include?(parts[1])
    next unless user_to_ldap.include?(parts[0])

    is_multi = PERMIT_MULTIPLE.include?(parts[0])
    field = user_to_ldap[parts[0]]
    value = is_multi ? parts[2].split(',') : parts[2]

    case parts[1]
      when 'starts'
        next if is_multi
        out << "(#{field}=#{LdapModel.ldap_escape(value)}*)"
      when 'ends'
        next if is_multi
        out << "(#{field}=*#{LdapModel.ldap_escape(value)})"
      when 'contains'
        next if is_multi
        out << "(#{field}=*#{LdapModel.ldap_escape(value)}*)"
      when 'is'
        if value.class == Array
          if value.count > 1
            # multiple values OR'd together
            mvalue = value.map { |v| "(#{field}=#{LdapModel.ldap_escape(v)})" }
            out << "(|#{mvalue.join})"
            puavoid = value if parts[0] == 'id'
          else
            out << "(#{field}=#{LdapModel.ldap_escape(value[0])})"
            puavoid << value[0] if parts[0] == 'id'
          end
        else
          out << "(#{field}=#{LdapModel.ldap_escape(value)})"
          puavoid << value if parts[0] == 'id'
        end
    end
  end

  # This must be always in the query for reasons I'm not entirely familiar with
  out.unshift("(objectclass=#{base_class})")

  # Ensure these aren't strings
  puavoid.map!(&:to_i)

  return out, puavoid
end

# Builds a filter string for LDAP searches
def v4_combine_filter_parts(parts)
  (parts && parts.class == Array) ? "(&#{parts.join})" : "(objectclass=*)"
end

def v4_ensure_is_array(out, *members)
  # ensure these are always arrays, even if they have only one element or they're empty
  # leave them alone only if they're nil
  out.each do |o|
    members.each do |m|
      next unless o.include?(m)

      if o[m].nil?
        next
      elsif o[m].class != Array
        o[m] = [o[m]]
      end
    end
  end

  return out
end

# Not used at the moment, but tested and works
def v4_get_json_body(request)
  body = request.body.read

  if body.nil? || body.empty?
    raise V4_MissingParameter, 'missing request body'
  end

  return JSON.parse(body)
end

# Converts one raw LDAP attribute value to the specified user type
def v4_convert_ldap_string(value, type)
  case type
    when :integer
      return value.to_i

    when :float
      return value.to_f

    # FIXME: I don't think this is needed
    when :string
      return value.to_s.force_encoding('UTF-8')

    when :id_from_dn
      # extract the "XXX" from "puavoId=XXX,ou=Groups,dc=edu,dc=hogwarts,dc=net" if possible
      md = value.match(/puavoId=\d+/)

      if md
        temp = md[0]
        return temp[temp.index('=') + 1 .. -1].to_i
      else
        return -1
      end

    when :boolean
      if value == 'TRUE'
        return true
      else
        return false
      end

    #when :roles_array
    #  return value #['foo', 'bar']

    when :ldap_timestamp
      return Time.parse(value).to_i

    #when :ensure_array
      # TODO: figure out how to ensure single-element values will be converted to arrays,
      # but multi-element arrays are not converted to nested arrays

      #return value.class == Array ? value : [value]

    when :json
      return JSON.parse(value) rescue nil

    else
      return value
  end
end

# Converts user-specified field names to LDAP attributes
def v4_user_to_ldap(user_fields, conversion_table)
  ldap_attrs = []

  user_fields.each do |uf|
    if conversion_table.include?(uf)
      ldap_attrs << conversion_table[uf]
    end
  end

  return ldap_attrs
end

# Converts LDAP attributes to specified user types
def v4_ldap_to_user(raw_ldap_entries, requested_ldap_attrs, conversion_table)
  out = []

  raw_ldap_entries.each do |entry|
    converted = {}

    # convert the requested fields from LDAP attributes
    requested_ldap_attrs.each do |attr_name|
      unless conversion_table.include?(attr_name)
        # skip unlisted attributes
        # (this shouldn't happen, as raw_filter() will only return those attributes
        # we specifically asked for, but better safe than sorry)
        next
      end

      # how should this value be converted?
      definition = conversion_table[attr_name]
      user_name = definition[:name]
      type = definition[:type] || nil
      is_array = definition[:is_array] || false

      unless entry.include?(attr_name)
        # this entry does not have this attribute, but it was requested, so nil it is
        converted[user_name] = nil
      else
        # get the raw value
        value = entry[attr_name]

        # sigh... tell Ruby that these strings are already UTF-8
        value = value.map do |v|
          v.force_encoding('UTF-8') if v.class == String
        end

        # type conversion, if specified
        if type
          if value.class == Array
            value.map! do |v|
              v4_convert_ldap_string(v, type)
            end
          else
            value = v4_convert_ldap_string(value, type)
          end
        end

        # convert single-element arrays (LDAP just loves those for some reason) to
        # plain values unless the value has been permitted to be an array
        if !is_array && value.class == Array && value.count == 1
          value = value[0]
        end

        converted[user_name] = value
      end
    end

    out << converted
  end

  return out
end

# Removes items form hash whose keys are not on the set of allowed keys
def v4_purify_hash(hash, allowed_keys)
  out = {}

  hash.each do |k, v|
    if allowed_keys.include?(k)
      out[k] = v
    end
  end

  return out
end

# Do an operation, with common exception handling
def v4_do_operation(&block)
  begin
    return block.call()
  rescue NotFound => e
    return 404, json({
      status: 'error',
      error: {
        code: 'not_found',
        detail: e.to_s,
      },
      data: nil,
    })
  rescue V4_MissingFields => e
    return 400, json({
      status: 'error',
      error: {
        code: 'missing_fields',
        detail: 'missing or empty \"fields\" parameter',
      },
      data: nil,
    })
  rescue V4_UnknownField => e
    return 400, json({
      status: 'error',
      error: {
        code: 'unknown_parameter',
        detail: e.to_s,
      },
      data: nil,
    })
  rescue V4_MissingParameter => e
    return 400, json({
      status: 'error',
      error: {
        code: 'missing_parameter',
        detail: e.to_s,
      },
      data: nil,
    })
  rescue V4_InvalidParameter => e
    return 400, json({
      status: 'error',
      error: {
        code: 'invalid_parameter',
        detail: e.to_s,
      },
      data: nil,
    })
  rescue V4_DuplicateParameter => e
    return 400, json({
      status: 'error',
      error: {
        code: 'duplicate_parameter',
        detail: e.to_s,
      },
      data: nil,
    })
  rescue JSON::ParserError => e
    return 400, json({
      status: 'error',
      error: {
        code: 'bad_json',
      },
      data: nil,
    })
  rescue StandardError => e
    puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"

    return 500, json({
      status: 'error',
      error: {
        code: 'unknown_error',
        detail: e.to_s,
      },
      data: nil,
    })
  end

  # Not reached
end
