
Given /^I have been redirected to (.*)$/ do |page_name|
  # visit(url = nil, http_method = :get, data = {})
  visit( path_to(page_name), :get, { :client_id => 'fXLDE4FKas42DFgsfhRTfdlizK7oEm', :scope => 'read:presonalInfo', :redirect_uri => 'http://www.example2.com', :state => '123456789', :response_type => 'code', :approval_prompt => 'auto', :access_type => 'offline'  } )

end

Then /^I should get OAuth access token$/ do
  params = request.params
  #debugger
  params[:redirect_uri].should contain("http://www.example2.com")
  #params[:redirect_to].should =~ /^.*http:\/\/www.example1.com/
  visit( oauth_access_token_path, :post, { :client_id => 'fXLDE3FKas42DFgsfhRTfdlizK7oEm' , :client_secret => 'zK7oEm34gYk3hA54DKX8da4', 
                      :grant_type => 'authorization_code', :code => params[:code], 
                      :redirect_uri => 'http://www.example2.com', :approval_prompt => 'force' }) 
  debugger
  response.should contain("testi")
  #pending # express the regexp above with the code you wish you had
end

