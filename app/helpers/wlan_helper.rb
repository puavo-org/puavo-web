require 'base64'
require 'digest'

module WlanHelper
  def wlan_certfile_md5(base64encoded_data)
    Digest::MD5.hexdigest( Base64.decode64(base64encoded_data) )
  end

  def wlan_certfile_size(base64encoded_data)
    Base64.decode64(base64encoded_data).size
  end
end
