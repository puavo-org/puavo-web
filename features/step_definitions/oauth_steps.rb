Given /^I have been redirected to (.*) from "([^\"]*)"$/ do |page_name, client_name|
  @oauth_client = OauthClient.find( :first,
                                    :attribute => 'displayName',
                                    :value => client_name )
  visit( url_for(:controller => :oauth,
                 :action => :authorize,
                 :client_id => "oauth_client_id/example/" + @oauth_client.puavoOAuthClientId,
                 :scope => @oauth_client.puavoOAuthScope,
                 :redirect_uri => 'http://www.example2.com',
                 :state => '123456789',
                 :response_type => 'code',
                 :approval_prompt => 'auto',
                 :access_type => 'offline'  ) )
end

Then /^I should get OAuth Authorization Code$/ do
  params = CGI::parse( URI.parse( page.headers["Location"]).query )

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-26#section-4.1.2
  params["code"].first.should_not be_nil
  params["state"].first.should_not be_nil

  @authorization_code = params["code"].first
end

Then /^I should get OAuth Access Token with Authorization Code$/ do

  page.driver.browser.basic_authorize(
    "oauth_client_id/example/" + @oauth_client.puavoOAuthClientId,
    'zK7oEm34gYk3hA54DKX8da4'
  )

  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'authorization_code',
           :code => @authorization_code,
           :redirect_uri => 'http://www.example2.com',
           :approval_prompt => 'force' })

  page.status.should == "200 OK"

  data = JSON.parse( page.body )
  data["token_type"].should == "Bearer"
  data["expires_in"].should_not be_nil
  data["access_token"].should_not be_nil
  data["refresh_token"].should_not be_nil

  @refresh_token = data["refresh_token"]
  @access_token = data["access_token"]
end

Then /^I should get "([^\"]*)" information with Access Token$/ do |uid|
  cookies.clear
  header "HTTP_AUTHORIZATION", "Bearer #{ @access_token }"
  visit(whoami_path(:format => :json))
  page.status.should == "200 OK"
  data = JSON.parse(page.body)
  data["error"].should be_nil
  data["uid"].should == uid
end



Then /^I should get a new Access Token and a new Refresh Token with existing Refresh Token$/ do

  page.driver.browser.basic_authorize(
    "oauth_client_id/example/" + @oauth_client.puavoOAuthClientId,
    'zK7oEm34gYk3hA54DKX8da4'
  )
  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'refresh_token',
           :refresh_token => @refresh_token
         }
  )

  data = JSON.parse( page.body )
  data["token_type"].should == "Bearer"
  data["expires_in"].should_not be_nil
  data["access_token"].should_not be_nil
  data["refresh_token"].should_not be_nil

  @refresh_token = data["refresh_token"]
  @access_token = data["access_token"]
end




Then /^I should not get OAuth Access Token with expired Authorization Code$/ do

  page.driver.browser.basic_authorize(
    "oauth_client_id/example/" + @oauth_client.puavoOAuthClientId,
    'zK7oEm34gYk3hA54DKX8da4'
  )

  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'authorization_code',
           :code => @authorization_code,
           :redirect_uri => 'http://www.example2.com',
           :approval_prompt => 'force' })


  # TODO 401
  page.status.should_not == "200 OK"

  data = JSON.parse( page.body )
  data["error"].should_not be_nil

end


Then /^I should not get "([^\"]*)" information with expired Access Token$/ do |uid|
  cookies.clear
  header "HTTP_AUTHORIZATION", "Bearer #{ @access_token }"
  visit(whoami_path(:format => :json))

  # TODO 401
  page.status.should_not == "200 OK"
  data = JSON.parse(page.body)
  data["error"].should_not be_nil
end

Then /^I should not get a new Access Token and a new refresh Token with expired refresh Token$/ do

  page.driver.browser.basic_authorize(
    "oauth_client_id/example/" + @oauth_client.puavoOAuthClientId,
    'zK7oEm34gYk3hA54DKX8da4'
  )

  visit( oauth_access_token_path(:format => :json),
         :post, {
           :grant_type => 'refresh_token',
           :refresh_token => @refresh_token
         }
  )

  page.status.should_not == "200 OK"
  data = JSON.parse( page.body )
  data["error"].should_not be_nil
end
