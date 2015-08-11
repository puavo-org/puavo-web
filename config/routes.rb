PuavoUsers::Application.routes.draw do

  match "/500", :to => "errors#unhandled_exception"

  root :to => "schools#index"

  match '/menu' => 'menu#index', :via => :get

  scope :path => "restproxy" do
    match '(*url)' => 'rest#proxy'
  end

  scope :path => "users" do
    resources :ldap_services
    resource :organisation_external_services

    scope :path => ':school_id' do
      match 'roles/:id/select_school' => 'roles#select_school', :as => :select_school_role, :via => :get
      match 'roles/:id/select_role' => 'roles#select_role', :as => :select_role_role, :via => :post
      match 'roles/:id/add_group/:group_id' => 'roles#add_group', :as => :add_group_role, :via => :put
      match 'roles/:id/remove_group/:group_id' => 'roles#remove_group', :as => :remove_group_role, :via => :put
      match 'roles/:id/remove_users' => 'roles#remove_users', :as => :remove_users_role, :via => :put
    end

    scope :path => ':school_id' do
      resource :rename_groups
      resources :roles
    end
    resources :roles

    namespace :schools do
      scope :path => ':school_id' do
        resource :external_services
      end
    end

    scope :path => ':school_id' do
      resources :printer_permissions
    end


    match 'schools/:id/admins' => 'schools#admins', :as => :admins_school, :via => :get
    match 'schools/:id/add_school_admin/:user_id' => 'schools#add_school_admin', :as => :add_school_admin_school, :via => :put
    match 'schools/:id/remove_school_admin/:user_id' => 'schools#remove_school_admin', :as => :remove_school_admin_school, :via => :put
    match 'schools/:id/wlan' => 'schools#wlan', :as => :wlan_school, :via => :get
    match 'schools/:id/wlan_update' => 'schools#wlan_update', :as => :wlan_update_school, :via => :put
    match 'schools/:id/external_services' => 'external_services#index', :as => :external_services_school, :via => :get
    match 'schools/:id/import_tool' => 'import_tool#index', :via => :get
    resources :schools

    scope :path => ':school_id' do
      match 'groups/:id/members' => 'groups#members', :as => :add_role_group, :via => :get
      match 'groups/:id/add_role/:role_id' => 'groups#add_role', :as => :add_role_group, :via => :put
      match 'groups/:id/delete_role/:role_id' => 'groups#delete_role', :as => :delete_role_group, :via => :put
      match 'users/:id/select_school' => 'users#select_school', :as => :select_school_user, :via => :get
      match 'users/:id/select_role' => 'users#select_role', :as => :select_role_user, :via => :post
      match 'users/change_school' => 'users#change_school', :as => :change_school_users, :via => :post
    end


    scope :path => ':school_id' do
      resources :users
      match 'users/:id/image' => 'users#image', :as => :image_user, :via => :get
    end

    resources :users

    scope :path => ':school_id' do
      resources :groups
    end
    resources :groups

    match '/login' => 'sessions#new', :as => :login, :via => :get
    match '/login' => 'sessions#create', :as => :login, :via => :post
    match '/logout' => 'sessions#destroy', :as => :logout, :via => :delete
    match '/logo' => 'sessions#logo', :as => :logo, :via => :get, :format => :png
    match '/login/helpers' => 'sessions#login_helpers', :as => :login_helpers, :via => :get, :format => :js
    match '/login/theme' => 'sessions#theme', :as => :login_theme, :via => :get, :format => :css

    resources :sessions
    match 'schools/:id/image' => 'schools#image', :as => :image_school, :via => :get
    match '/' => 'schools#index'
    match ':school_id/users/import/refine' => 'users/import#refine', :as => :refine_users_import, :via => :post
    match ':school_id/users/import/validate' => 'users/import#validate', :as => :validate_users_import, :via => [:post]
    match ':school_id/users/import/new' => 'users/import#new', :as => :new_users_import, :via => :get
    match ':school_id/users/import/status/:job_id' => 'users/import#status', :as => :import_status, :via => :get
    match ':school_id/users/import/render_pdf/:job_id' => 'users/import#render_pdf', :as => :render_pdf, :via => :post
    match ':school_id/users/import/' => 'users/import#create', :as => :create_users_import, :via => :post
    match ':school_id/users/import/user_validate' => 'users/import#user_validate', :as => :user_validate_users_import, :via => :post
    match ':school_id/users/import/options' => 'users/import#options', :as => :options_users_import, :via => :get
    match ':school_id/users/import/download' => 'users/import#generate_passwords_pdf', :as => :generate_passwords_pdf, :via => :post

    scope :path => "password" do
      get( '', :to => 'password#edit',
           :as => :password )
      get( 'edit',
           :to => 'password#edit',
           :as => :edit_password )
      get( 'own',
           :to => 'password#own',
           :as => :own_password )
      put( '',
           :to => 'password#update' )
      get( 'forgot',
           :to => 'password#forgot',
           :as => :forgot_password )
      put( 'forgot',
           :to => 'password#forgot_send_token',
           :as => :forgot_send_token_password )
      get( ':jwt/reset',
           :to => 'password#reset',
           :as => :reset_password,
           constraints: { jwt: /.+/ } )
      post( ':jwt/reset',
            :to => 'password#reset_update',
            :as => :reset_update_password,
            constraints: { jwt: /.+/ } )
      get( 'successfully/:message',
           :to => 'password#successfully',
           :as => :successfully_password )
    end

    match( 'email_confirm' => 'email_confirm#confirm',
           :as => :confirm_email,
           :via => :put )
    match( 'email_confirm/successfully' => 'email_confirm#successfully',
           :as => :successfully_email_confirm,
           :via => :get )
    match( 'email_confirm/:jwt' => 'email_confirm#preview',
           :as => :preview_email_confirm,
           :via => :get,
           :constraints => { jwt: /.+/ } )

    match 'themes/:theme' => 'themes#set_theme', :as => :set_theme
    resources :admins

    match 'owners' => 'organisations#owners', :as => :owners_organisation, :via => :get
    match 'remove_owner/:user_id' => 'organisations#remove_owner', :as => :remove_owner_organisations, :via => :put
    match 'add_owner/:user_id' => 'organisations#add_owner', :as => :add_owner_organisations, :via => :put

    match 'wlan' => 'organisations#wlan', :as => :wlan_organisation, :via => :get
    match 'wlan_update' => 'organisations#wlan_update', :as => :wlan_update_organisation, :via => :put

    resource :organisation, :only => [:show, :edit, :update]
    match "search" => "users_search#index", :as => :search_index
    resource :profile, :only => [:edit, :update, :show]
    match 'profile/image' => 'profiles#image', :as => :image_profile, :via => :get
  end

  scope :path => "devices" do
    match '/' => 'schools#index'
    match 'sessions/show' => 'api/v1/sessions#show', :via => :get
    resources :sessions

    match 'hosts/types' => 'hosts#types'

    scope :path => ':school_id' do
      match 'devices/:id/select_school' => 'devices#select_school', :as => 'select_school_device', :via => :get
      match 'devices/:id/change_school' => 'devices#change_school', :as => 'change_school_device', :via => :post
      match 'devices/:id/image' => 'devices#image', :as => 'image_device', :via => :get

      resources :devices

      match( 'devices/:id/revoke_certificate' => 'devices#revoke_certificate',
             :as => 'revoke_certificate_device',
             :via => :delete )

    end
    
    match 'servers/:id/image' => 'servers#image', :as => 'image_server', :via => :get
    match( 'servers/:id/revoke_certificate' => 'servers#revoke_certificate',
           :as => 'revoke_certificate_server',
           :via => :delete )
    resources :servers

    namespace :api do
      namespace :v2 do
        match( 'devices/by_hostname/:hostname' => 'devices#by_hostname',
               :as => 'by_hostname_api_v2_device',
               :via => :get )
        resources :devices
        resources :servers
      end
    end

    resources :printers, :except => [:show, :new]

    match "search" => "devices_search#index"

    match '/auth' => 'sessions#auth', :via => :get
    
  end

    namespace :api do
      namespace :v2 do
        match( 'hosts/sign_certificate' => 'hosts#sign_certificate',
               :as => 'hosts_sign_certificate',
               :via => :post,
               :format => :json )
      end
    end

  ["api/v2/", ""].each do |prefix|
    match("#{ prefix }external_files" => "external_files#index", :via => :get)
    match("#{ prefix }external_files" => "external_files#upload", :via => :post)
    match(
      "#{ prefix }external_files/:name" => "external_files#get_file",
      :name => /.+/,
      :format => false,
      :via => :get,
      :as => "download_external_file"
    )
    match(
      "#{ prefix }external_files/:name" => "external_files#destroy",
      :name => /.+/,
      :format => false,
      :via => :delete,
      :as => "destroy_external_file"
    )
  end

end
