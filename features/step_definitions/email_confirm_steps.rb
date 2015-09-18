Given(/^generate new email confirm token for user "(.*?)" with "(.*?)" with secret "(.*?)"$/) do |username, email, secret|
  jwt_data = {
    "iat" => Time.now.to_i.to_s,

    "username" => username,
    "organisation_domain" => "example.opinsys.net",
    "email" => email
  }
  @jwt = JWT.encode(jwt_data, secret)
end

Given(/^mock email confirm service for user "(.*?)" with email "(.*?)"$/) do |username, email|
  stub_request(:post, "http://127.0.0.1:9393/email_confirm").
    with(:body => { "username" => username,"email" => email },
         :headers => {
           'Accept-Language'=>'en',
           'Host'=>'www.example.com'
         }).
    to_return(:status => 200,
              :body => { :status => 'successfully' }.to_json,
              :headers => {})
end
