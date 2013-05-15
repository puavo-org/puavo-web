Dir.glob(File.dirname(__FILE__) + "/*_test.rb").each do |t|
  require "./" + t
end
