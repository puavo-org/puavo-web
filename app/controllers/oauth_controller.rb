class OauthController < ApplicationController
  before_filter :set_organisation_to_session, :set_locale

  skip_before_filter :ldap_setup_connection

  skip_before_filter :login_required
  skip_before_filter :find_school
  skip_before_filter :set_authorization_user

  skip_after_filter :remove_ldap_connection

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
    # this post comes from the browser from the login page, or the login method
    # give the code, redirect to client software
    @code = UUID.new.generate 
    user = User.find( :first, :attribute => 'uid', :value => params[:user][:uid])
    begin
       user.bind( params[:user][:password] ) 
       access_code = AccessCode.create( :access_code => @code, :client_id => params[:client_id], :user_dn => user.dn.to_s)
       # TODO: must consider if the redirect_url should be verified against the database
       # render :text => params.inspect
       redirect_to params[:redirect_uri] + url_for(:jee => "juu", :foo => "foobar")
    rescue
       flash[:notice] = t('flash.session.failed')
       render :action => :login
    end
  end

  # POST /oauth/authorize
  def token 
    logger.debug "\n\nAUTHORIZE POST\n\n" + params.inspect
    render :text => 'testi'
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
