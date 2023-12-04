# Multi-factor Authentication

module Puavo
  module MFA
    # Sends a request to the MFA server. You have to handle the response yourself.
    # "method" can be :post, :get, or other similar HTTP method. "data" can be used
    # to send JSON in the request body if the HTTP method supports it.
    def self.mfa_call(request_id, method, url, data: nil)
      http = HTTP
        .auth("Bearer #{CONFIG['mfa_server']['bearer_key']}")
        .headers('X-Request-ID' => request_id)

      full_url = "#{CONFIG['mfa_server']['address']}/v1/#{url}"

      response = data.nil? ?
        http.send(method, full_url) :
        http.send(method, full_url, json: data)   # not all methods can have data in body

      return response, JSON.parse(response.body.to_s)
    end
  end
end
