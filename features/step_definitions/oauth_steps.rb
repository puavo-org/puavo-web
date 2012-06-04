
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

Then /^I should get OAuth access code$/ do
  params = CGI::parse( URI.parse( response.headers["Location"]).query )

  # response.body.should contain("http://www.example2.com")
  params["code"].first.should_not be_nil
  params["state"].first.should_not be_nil

  @access_code = params["code"].first
end

Then /^I should get OAuth access token with access code$/ do
  params = request.params
  params[:redirect_uri].should contain("http://www.example2.com")

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.2
  request.params["response_type"].should == "code"

  basic_auth("oauth_client_id/" + @oauth_client.puavoOAuthClientId, 'zK7oEm34gYk3hA54DKX8da4')

  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'authorization_code',
           :code => @access_code,
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

Then /^I should get "([^\"]*)" information with access token$/ do |uid|
  cookies.clear
  header "HTTP_AUTHORIZATION", "token #{ @access_token }"
  visit(whoami_path)
  response.status.should == "200 OK"
  data = JSON.parse(response.body)
  data["error"].should be_nil
  data["uid"].should == uid
end



Then /^I should get a new access token and a new refresh token with existing refresh token$/ do

  basic_auth("oauth_client_id/" + @oauth_client.puavoOAuthClientId, 'zK7oEm34gYk3hA54DKX8da4')
  visit( oauth_refresh_access_token_path(:format => :json),
         :post, {
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
