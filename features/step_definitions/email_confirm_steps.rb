Given(/^generate new email confirm token for user "(.*?)" with "(.*?)"$/) do |username, email|
  jwt_data = {
    "iat" => Time.now.to_i.to_s,

    "username" => username,
    "organisation_domain" => "www.example.net",
    "email" => email
  }
  @jwt = JWT.encode(jwt_data, "secret")
end
