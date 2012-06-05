Given /^I have been redirected to (.*) from "([^\"]*)"$/ do |page_name, client_name|
  @oauth_client = OauthClient.find( :first,
                                    :attribute => 'displayName',
                                    :value => client_name )
  visit( url_for(:controller => :oauth,
                 :action => :authorize,
                 :client_id => "oauth_client_id/" + @oauth_client.puavoOAuthClientId,
                 :scope => @oauth_client.puavoOAuthScope,
                 :redirect_uri => 'http://www.example2.com',
                 :state => '123456789',
                 :response_type => 'code',
                 :approval_prompt => 'auto',
                 :access_type => 'offline'  ) )
end

Then /^I should get OAuth Authorization Code$/ do
  params = CGI::parse( URI.parse( response.headers["Location"]).query )

  # response.body.should contain("http://www.example2.com")
  params["code"].first.should_not be_nil
  params["state"].first.should_not be_nil

  @authorization_code = params["code"].first
end

Then /^I should get OAuth Access Token with Authorization Code$/ do
  params = request.params
  params[:redirect_uri].should contain("http://www.example2.com")

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.2
  request.params["response_type"].should == "code"

  basic_auth("oauth_client_id/" + @oauth_client.puavoOAuthClientId, 'zK7oEm34gYk3hA54DKX8da4')

  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'authorization_code',
           :code => @authorization_code,
           :redirect_uri => 'http://www.example2.com',
           :approval_prompt => 'force' })

  response.status.should == "200 OK"

  data = JSON.parse( response.body )
  data["token_type"].should == "Bearer"
  data["expires_in"].should_not be_nil
  data["access_token"].should_not be_nil
  data["refresh_token"].should_not be_nil

  @refresh_token = data["refresh_token"]
  @access_token = data["access_token"]
end

Then /^I should get "([^\"]*)" information with Access Token$/ do |uid|
  cookies.clear
  header "HTTP_AUTHORIZATION", "token #{ @access_token }"
  visit(whoami_path(:format => :json))
  response.status.should == "200 OK"
  data = JSON.parse(response.body)
  data["error"].should be_nil
  data["uid"].should == uid
end



Then /^I should get a new Access Token and a new Refresh Token with existing Refresh Token$/ do

  basic_auth("oauth_client_id/" + @oauth_client.puavoOAuthClientId, 'zK7oEm34gYk3hA54DKX8da4')
  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'refresh_token',
           :refresh_token => @refresh_token
         }
  )

  data = JSON.parse( response.body )
  data["token_type"].should == "Bearer"
  data["expires_in"].should_not be_nil
  data["access_token"].should_not be_nil
  data["refresh_token"].should_not be_nil

  @refresh_token = data["refresh_token"]
  @access_token = data["access_token"]
end




Then /^I should not get OAuth Access Token with expired Authorization Code$/ do
  params = request.params
  params[:redirect_uri].should contain("http://www.example2.com")

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.2
  request.params["response_type"].should == "code"

  basic_auth("oauth_client_id/" + @oauth_client.puavoOAuthClientId, 'zK7oEm34gYk3hA54DKX8da4')

  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'authorization_code',
           :code => @authorization_code,
           :redirect_uri => 'http://www.example2.com',
           :approval_prompt => 'force' })


  # TODO 401
  response.status.should_not == "200 OK"

  data = JSON.parse( response.body )
  data["error"].should_not be_nil

end


Then /^I should not get "([^\"]*)" information with expired Access Token$/ do |uid|
  cookies.clear
  header "HTTP_AUTHORIZATION", "token #{ @access_token }"
  visit(whoami_path(:format => :json))

  # TODO 401
  response.status.should_not == "200 OK"
  data = JSON.parse(response.body)
  data["error"].should_not be_nil
end
