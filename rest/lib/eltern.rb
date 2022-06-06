# Utility stuff for puavo-eltern

require 'net/http'

module PuavoRest

module ElternHelpers
  def eltern_authenticate(username, password, request_id)
    do_eltern_request(request_id,
                      CONFIG['eltern_sso']['server'],
                      CONFIG['eltern_sso']['auth'],
                      :post, { 'email' => username, 'password' => password })
  end

  def eltern_get_all_users(request_id)
    do_eltern_request(request_id,
                      CONFIG['eltern_users']['server'],
                      CONFIG['eltern_users']['auth'],
                      :get)
  end

  private

  # Generic HTTP(S) POST/GET wrapper with timeouts and retries. Returns nil if the request failed,
  # otherwise returns the JSON the server sent.
  def do_eltern_request(request_id, url, auth, method, post_body=nil)
    attempt = 1

    begin
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.instance_of?(URI::HTTPS)
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      # Don't get stuck for too long if puavo-eltern isn't responding
      http.open_timeout = 5
      http.read_timeout = 10

      case method
        when :post
          request = Net::HTTP::Post.new(uri.request_uri)

        when :get
          request = Net::HTTP::Get.new(uri.request_uri)

        else
          rlog.error("[#{request_id}] do_eltern_request(): invalid request method #{method.inspect}")
          return nil
      end

      request.add_field('Host', 'eltern.harz.schule')
      request.add_field('Authorization', CONFIG['eltern_sso']['auth']['token'])

      # This isn't a form submission
      request.add_field('Content-Type', 'application/json')

      if post_body && method == :post
        request.body = post_body.to_json
      end

      rlog.info("[#{request_id}] do_eltern_request(): sending request to \"#{uri.to_s}\"")

      response = http.request(request)
      rlog.info("[#{request_id}] do_eltern_request(): response status: #{response.code}")

      data = response.body

      if response.code != '200'
        rlog.error("[#{request_id}] do_eltern_request(): error response: #{data.inspect}")
        return nil
      end

      begin
        data = JSON.parse(data)
      rescue => e
        rlog.error("[#{request_id}] do_eltern_request(): can't parse the response JSON: #{e}")
        return nil
      end

      return data
    rescue => e
      rlog.error("[#{request_id}] do_eltern_request(): request failed: #{e}")

      # Retry to weed out intermittent network errors
      if attempt < 3
        rlog.info("[#{request_id}] do_eltern_request(): attempt #{attempt + 1} in 1 second...")
        attempt += 1
        sleep 1
        retry
      else
        rlog.error("[#{request_id}] do_eltern_request(): all attempts used, giving up")
        return nil
      end
    end
  end

end   # module ElternLib

end   # module PuavoRest
