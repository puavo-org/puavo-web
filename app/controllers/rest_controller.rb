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

    rest_url = "#{ Puavo::CONFIG["puavo_rest"]["host"] }/#{ params["url"] }#{ qs }"
    puts "Proxying connection to #{ rest_url }"

    method = {"GET" => :get, "POST" => :post}[request.method]

    options = {}

    if method == :post
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
