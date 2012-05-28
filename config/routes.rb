ActionController::Routing::Routes.draw do |map|
  map.resources :oauth_clients

  map.resource :rename_groups, :path_prefix => ':school_id'

  map.resources :external_services

  map.select_school_role( 'roles/:id/select_school',
                          :controller => 'roles',
                          :action => 'select_school',
                          :path_prefix => ':school_id',
                          :conditions => { :method => :get } )
  map.select_role_role( 'roles/:id/select_role',
                        :controller => 'roles',
                        :action => 'select_role',
                        :path_prefix => ':school_id',
                        :conditions => { :method => :post } )
  map.add_group_role( 'roles/:id/add_group/:group_id',
                      :controller => 'roles',
                      :action => 'add_group',
                      :path_prefix => ':school_id',
                      :conditions => { :method => :put } )
  map.remove_group_role( 'roles/:id/remove_group/:group_id',
                         :controller => 'roles',
                         :action => 'remove_group',
                         :path_prefix => ':school_id',
                         :conditions => { :method => :put } )

  map.resources :roles, :path_prefix => ':school_id'

  map.admins_school( 'schools/:id/admins.:format',
                     :controller => 'schools',
                     :action => 'admins',
                     :conditions => { :method => :get } )
  map.add_school_admin_school('schools/:id/add_school_admin/:user_id.:format',
                              :controller => 'schools',
                              :action => 'add_school_admin',
                              :conditions => { :method => :put } )
  map.remove_school_admin_school('schools/:id/remove_school_admin/:user_id.:format',
                              :controller => 'schools',
                              :action => 'remove_school_admin',
                              :conditions => { :method => :put } )
  map.resources :schools

  map.add_role_group( 'groups/:id/members.:format',
                      :controller => 'groups',
                      :action => 'members',
                      :path_prefix => ':school_id',
                      :conditions => { :method => :get } )
  map.add_role_group( 'groups/:id/add_role/:role_id',
                      :controller => 'groups',
                      :action => 'add_role',
                      :path_prefix => ':school_id',
                      :conditions => { :method => :put } )
  map.delete_role_group( 'groups/:id/delete_role/:role_id',
                         :controller => 'groups',
                         :action => 'delete_role',
                         :path_prefix => ':school_id',
                         :conditions => { :method => :put } )

  map.select_school_user( 'users/:id/select_school',
                          :controller => 'users',
                          :action => 'select_school',
                          :path_prefix => ':school_id',
                          :conditions => { :method => :get } )
  map.select_role_user( 'users/:id/select_role',
                        :controller => 'users',
                        :action => 'select_role',
                        :path_prefix => ':school_id',
                        :conditions => { :method => :post } )
  map.change_school_users( 'users/change_school',
                           :controller => 'users',
                           :action => 'change_school',
                           :path_prefix => ':school_id',
                           :conditions => { :method => :post } )
  map.resources :users, :path_prefix => ':school_id'

  map.image_user( 'users/:id/image',
                      :controller => 'users',
                      :action => 'image',
                      :path_prefix => ':school_id',
                      :conditions => { :method => :get } )
  map.resources :users

  map.resources :groups, :path_prefix => ':school_id'
  map.resources :groups

  map.login '/login', :controller => 'sessions', :action => 'new'
  map.logout '/logout', :controller => 'sessions', :action => 'destroy'

  map.resources :sessions

  map.image_school( 'schools/:id/image',
                      :controller => 'schools',
                      :action => 'image',
                      :conditions => { :method => :get } )
  map.root :controller => "schools"

  map.with_options :controller => 'users/import' do |import|
    import.refine_users_import(
                               ":school_id/users/import/refine",
                               :action => 'refine',
                               :conditions => {:method => :post} )
    import.validate_users_import(
                                 ":school_id/users/import/validate",
                                 :action => 'validate',
                                 :conditions => {:method => [:post]} )# validate FIXME put method?
    import.users_import(
                        ":school_id/users/import/show",
                        :action => 'show',
                        :conditions => {:method => :get} )# preview
    import.new_users_import(
                            ":school_id/users/import/new",
                            :action => 'new',
                            :conditions => {:method => :get} )# preview
    import.create_users_import(
                               ":school_id/users/import/",
                               :action => 'create',
                               :conditions => {:method => :post} )# preview
    import.user_validate_users_import(
                               ":school_id/users/import/user_validate.:format",
                               :action => 'user_validate',
                               :conditions => {:method => :post} )
    import.options_users_import(
                               ":school_id/users/import/options.:format",
                               :action => 'options',
                               :conditions => {:method => :get} )
    import.download_users_import(
                                 ":school_id/users/import/download.:format",
                                 :action => 'download',
                                 :conditions => {:method => :get} )
  end

  map.with_options :controller => 'password' do |password|
    password.password "password", :action => 'edit', :conditions => {:method => :get}
    password.edit_password 'password/edit', :action => 'edit', :conditions => {:method => :get}
    password.own_password 'password/own', :action => 'own', :conditions => {:method => :get}
    password.connect 'password', :action => 'update', :conditions => {:method => :put}
  end

  map.with_options :controller => 'themes' do |theme|
    theme.set_theme "themes/:theme", :action => "set_theme"
  end

  map.resources :admins

  map.resource :organisation, :only => [:show, :edit, :update]

  map.resources :search, :only => [:index]

  map.resource :profile, :only => [:edit, :update, :show]

  map.with_options :controller => 'oauth' do |oauth|
    oauth.oauth_authorize "oauth/authorize", :action => 'authorize', :conditions => {:method => :get}
    oauth.oauth_access_token 'oauth/authorize', :action => 'code', :conditions => {:method => :post}
    oauth.oauth_refresh_access_token 'oauth/token', :action => 'refresh_token', :conditions => {:method => :post}
  end
end
