
Given /^I have been redirected to (.*)$/ do |page_name|
  visit( url_for(:controller => :oauth,
                 :action => :authorize,
                 :client_id => 'fXLDE5FKas42DFgsfhRTfdlizK7oEm',
                 :scope => 'read:presonalInfo',
                 :redirect_uri => 'http://www.example2.com',
                 :state => '123456789',
                 :response_type => 'code',
                 :approval_prompt => 'auto',
                 :access_type => 'offline'  ) )
end

Then /^I should get OAuth access token with access code$/ do
  params = request.params
  params[:redirect_uri].should contain("http://www.example2.com")
  visit( oauth_access_token_path(:format => :json),
         :post, {
           :client_id => 'fXLDE5FKas42DFgsfhRTfdlizK7oEm',
           :client_secret => 'zK7oEm34gYk3hA54DKX8da4',
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
  set_ldap_admin_connection
  user = User.find(:first, :attribute => "uid", :value => uid)
  cookies.clear
  header "Authorization", "token #{ @access_token }"
  visit("users/#{user.puavoId}.json")
  JSON.parse(response.body)["uid"].should == uid
end

Then /^I should get OAuth access code$/ do
  params = CGI::parse( URI.parse( response.headers["Location"]).query )

  # response.body.should contain("http://www.example2.com")
  params["code"].first.should_not be_nil
  params["state"].first.should_not be_nil

  @access_code = params["code"].first
end


Then /^I should get a new access token and a new refresh token with existing refresh token$/ do
  visit( oauth_refresh_access_token_path(:format => :json),
         :post, {
           :client_id => 'fXLDE5FKas42DFgsfhRTfdlizK7oEm',
           :client_secret => 'zK7oEm34gYk3hA54DKX8da4',
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
