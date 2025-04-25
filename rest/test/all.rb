# Warnings are good, unless they become spammy. Monkeypatch the warning message
# printer to suppress the annoying "not verifying SSL hostname of LDAPS server"
# warning, because it accomplishes nothing in the test environment, except it
# drowns out other warnings that might actually be serious.
module Warning
  def warn(msg)
    return unless msg
    return if msg.start_with?('not verifying SSL hostname')
    super
  end
end

Dir.glob(File.expand_path(File.dirname(__FILE__)) + "/*_test.rb").each do |p|
    puts "TEST #{ p }"
    require_relative p
end
