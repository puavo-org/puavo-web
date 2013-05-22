PuavoUsers::Application.routes.draw do


  root :to => "schools#index"

  match '/menu' => 'menu#index', :via => :get

  scope :path => "users" do
    resources :external_services

    scope :path => ':school_id' do
      match 'roles/:id/select_school' => 'roles#select_school', :as => :select_school_role, :via => :get
      match 'roles/:id/select_role' => 'roles#select_role', :as => :select_role_role, :via => :post
      match 'roles/:id/add_group/:group_id' => 'roles#add_group', :as => :add_group_role, :via => :put
      match 'roles/:id/remove_group/:group_id' => 'roles#remove_group', :as => :remove_group_role, :via => :put
    end

    scope :path => ':school_id' do
      resource :rename_groups
      resources :roles
    end
    resources :roles

    match 'schools/:id/admins' => 'schools#admins', :as => :admins_school, :via => :get
    match 'schools/:id/add_school_admin/:user_id' => 'schools#add_school_admin', :as => :add_school_admin_school, :via => :put
    match 'schools/:id/remove_school_admin/:user_id' => 'schools#remove_school_admin', :as => :remove_school_admin_school, :via => :put
    match 'schools/:id/wlan' => 'schools#wlan', :as => :wlan_school, :via => :get
    match 'schools/:id/wlan_update' => 'schools#wlan_update', :as => :wlan_update_school, :via => :put
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

    match '/login' => 'sessions#new', :as => :login
    match '/logout' => 'sessions#destroy', :as => :logout
    resources :sessions
    match 'schools/:id/image' => 'schools#image', :as => :image_school, :via => :get
    match '/' => 'schools#index'
    match ':school_id/users/import/refine' => 'users/import#refine', :as => :refine_users_import, :via => :post
    match ':school_id/users/import/validate' => 'users/import#validate', :as => :validate_users_import, :via => [:post]
    match ':school_id/users/import/show' => 'users/import#show', :as => :users_import, :via => :get
    match ':school_id/users/import/new' => 'users/import#new', :as => :new_users_import, :via => :get
    match ':school_id/users/import/' => 'users/import#create', :as => :create_users_import, :via => :post
    match ':school_id/users/import/user_validate' => 'users/import#user_validate', :as => :user_validate_users_import, :via => :post
    match ':school_id/users/import/options' => 'users/import#options', :as => :options_users_import, :via => :get
    match ':school_id/users/import/download' => 'users/import#download', :as => :download_users_import, :via => :get
    match 'password' => 'password#edit', :as => :password, :via => :get
    match 'password/edit' => 'password#edit', :as => :edit_password, :via => :get
    match 'password/own' => 'password#own', :as => :own_password, :via => :get
    match 'password' => 'password#update', :via => :put
    match 'themes/:theme' => 'themes#set_theme', :as => :set_theme
    resources :admins

    match 'wlan' => 'organisations#wlan', :as => :wlan_organisation, :via => :get
    match 'wlan_update' => 'organisations#wlan_update', :as => :wlan_update_organisation, :via => :put

    resource :organisation, :only => [:show, :edit, :update]
    match "search" => "users_search#index", :as => :search_index
    resource :profile, :only => [:edit, :update, :show]
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
        resources :devices
        resources :servers
      end
    end

    resources :printers, :except => [:show, :new]

    match "search" => "devices_search#index"

    match '/auth' => 'sessions#auth', :via => :get
    
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
