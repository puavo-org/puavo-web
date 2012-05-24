class OauthController < ApplicationController

  # GET /oauth/authorize
  def login
    # show login page if needed. Login page submit button takes us to the code function
    # otherwise handle then kerberos login and redirect to code
    respond_to do |format|
      if kerberos_ticket? 
        format.html { redirect_to( oauth_access_code_path ) } 
      else
        format.html
      end  
    end
  end

  # POST /oauth/code
  def code
    @code = 100000 + Random.rand(900000)
    # this post comes from the browser from the login page, or the login method
    # give the code, redirect to client software
  end

  # POST /oauth/authorize
  def token 
    # this post comes from the client
    # Here we exchange the code with the token
  end

  # POST /oauth/????
  def refresh_token
    # get new accesstoken by using refresh_token and user credentials
  end 

  def kerberos_ticket?
     false
  end
end
