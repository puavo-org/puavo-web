
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
           :code => @oauth_code,
           :redirect_uri => 'http://www.example2.com',
           :approval_prompt => 'force' })

  response.status.should == "200 OK"

  data = JSON.parse( response.body )
  data["token_type"].should == "Bearer"
  data["expires_in"].should_not be_nil
  data["access_token"].should_not be_nil

  @access_token = data["access_token"]
end

Then /^I should get "([^\"]*)" information with access token$/ do |uid|
  @access_token.should_not be_nil
  user = User.find(:first, :attribute => "uid", :value => uid)
  visit( "/users/#{user.puavoId}.json", :get )
  response.should contain("test")
end

Then /^I should get OAuth access code$/ do
  params = CGI::parse( URI.parse( response.headers["Location"]).query )

  # response.body.should contain("http://www.example2.com")
  params["code"].first.should_not be_nil
  params["state"].first.should_not be_nil

  @oauth_code = params["code"].first
end
