class RestController < ApplicationController

  def proxy

    qs = URI.parse(request.url).query || ""
    if !qs.empty?
      qs = "?" + qs
    end

    if !Puavo::CONFIG["puavo_rest"] || !Puavo::CONFIG["puavo_rest"]["host"]
      return render :status => 500, :json => {
        "error" => {
          "code" => "ConfigurationError",
          "message" => "puavo-rest host is not configured"
        }
      }
    end

    rest_path = "/#{ params["url"] }#{ qs }"

    method = request.method.downcase.to_sym

    options = {
      :headers => {
        "Content-type" => request.content_type
      }
    }

    if [:post, :put].include?(method)
      options[:body] = request.body.read
    end

    begin
      res = LdapOrganisation.current.rest_proxy.request(method, rest_path, options)
    rescue PuavoRestProxy::BadStatus => error
      res = error.response
    end

    response.headers.merge!(res.headers)
    render :text => res.to_s, :status => res.code
  end
end
