class Hash

  def recursive_symbolize_keys!
    self.symbolize_keys!
    self.each do |k, v|
      v.recursive_symbolize_keys! if v.is_a? Hash
    end
  end

end
