class Host
  def self.all
    Server.all + Device.all
  end
end
