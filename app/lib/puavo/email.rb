module Puavo
  module Email
    def self.email_management_host(path: nil)
      url = URI(Puavo::CONFIG['email_management']['host'])
      url.path = path if path
      url.to_s
    end
  end
end
