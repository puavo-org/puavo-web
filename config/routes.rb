ActionController::Routing::Routes.draw do |map|
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

  map.resources :users, :path_prefix => ':school_id'
  map.resources :users

  map.resources :groups, :path_prefix => ':school_id'

  map.login '/login', :controller => 'sessions', :action => 'new'
  map.logout '/logout', :controller => 'sessions', :action => 'destroy'

  map.resources :sessions

  map.root :controller => "schools"

  map.with_options :controller => 'users/import' do |import|
    import.refine_users_import(
                               ":school_id/users/import/refine",
                               :action => 'refine',
                               :conditions => {:method => :get} )
    import.validate_users_import(
                                 ":school_id/users/import/validate",
                                 :action => 'validate',
                                 :conditions => {:method => [:post, :get]} )# validate FIXME put method?
    import.role_users_import(
                              ":school_id/users/import/role",
                              :action => 'role',
                              :conditions => {:method => [:get, :put]} )# role
    import.preview_users_import(
                                ":school_id/users/import/preview",
                                :action => 'preview',
                                :conditions => {:method => :get} )# preview
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
  end

  map.with_options :controller => 'password' do |password|
    password.password ":school_id/password", :action => 'edit', :conditions => {:method => :get}
    password.edit_password ':school_id/password/edit', :action => 'edit', :conditions => {:method => :get}
    password.connect ':school_id/password', :action => 'update', :conditions => {:method => :put}
  end

  map.with_options :controller => 'themes' do |theme|
    theme.set_theme "themes/:theme", :action => "set_theme"
  end

  map.resources :admins
end
