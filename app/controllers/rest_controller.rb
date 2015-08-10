class RestController < ApplicationController
  def proxy

    qs = URI.parse(request.url).query || ""
    if !qs.empty?
      qs = "?" + qs
    end

    rest_url = "#{ Puavo::CONFIG["puavo_rest"]["host"] }/#{ params["url"] }#{ qs }"
    puts "Proxying connection to #{ rest_url }"

    res = HTTP.basic_auth({
        :user => session["uid"],
        :pass => session["password_plaintext"]
    }).get(rest_url, {
      :headers => {
        "host" => LdapOrganisation.first.puavoDomain
      }
    })

    response.headers.merge!(res.headers)
    render :text => res.to_s
  end
end
