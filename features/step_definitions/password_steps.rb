Given(/^mock password management service$/) do
  stub_request(:post, "http://127.0.0.1:9393/password/send_token?username=pavel").
    with(:headers => {'Accept-Language'=>'en', 'Host'=>'example.puavo.net'}).
    to_return( :status => 200,
               :body => { :status => 'successfully' }.to_json, :headers => {})

  stub_request(:put, "http://127.0.0.1:9393/password/change/#{ @jwt }").
        with(:body    => {'request_id'=>'ABCDEFGHIJ', 'new_password' => 'foobar'}.to_json,
             :headers => {'Accept-Language'=>'en', 'Host'=>'example.puavo.net'}).
        to_return(:status => 200, :body => "", :headers => {})
end

Given(/^generate new token for "(.*?)"$/) do |username|
  jwt_data = {
    iat: Time.now.to_i,
    id: 1,    # eh
    uid: username,
    domain: "example.puavo.net"
  }
  @jwt = JWT.encode(jwt_data, "secret")
end
