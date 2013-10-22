
class Hash
 # File activesupport/lib/active_support/core_ext/hash/keys.rb, line 30
 def symbolize_keys!
    keys.each do |key|
      self[(key.to_sym rescue key) || key] = delete(key)
    end
    self
  end

  # File activesupport/lib/active_support/core_ext/hash/keys.rb, line 24
  def symbolize_keys
    dup.symbolize_keys!
  end
end
