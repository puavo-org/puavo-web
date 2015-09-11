class RestController < ApplicationController

  HAS_BODY = [:post, :put]

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

    rest_url = "#{ Puavo::CONFIG["puavo_rest"]["host"] }/#{ params["url"] }#{ qs }"
    puts "Proxying connection to #{ rest_url }"

    method = request.method.downcase.to_sym

    options = {}

    if Puavo::CONFIG["puavo_rest"]["break_security"]
      options[:ssl] = { :verify_mode => OpenSSL::SSL::VERIFY_NONE }
    end

    if HAS_BODY.include?(method)
      options[:body] = request.body.read
    end

    res = HTTP.basic_auth({
        :user => session["uid"],
        :pass => session["password_plaintext"]
    }).send(method, rest_url, {
      :headers => {
        "host" => LdapOrganisation.first.puavoDomain,
        "Content-type" => request.content_type
      }
    }.merge(options))

    response.headers.merge!(res.headers)

    render :text => res.to_s, :status => res.code
  end
end
