Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  root :to => "schools#index"

  match '/menu' => 'menu#index', :via => :get

  get "/quick_search" => "quick_search#index" #, :as => :search_index
  get '/extended_search' => 'extended_search#index'
  post '/extended_search' => 'extended_search#do_search', via: [:options]

  post '/schools_mass_operations' => 'schools_mass_operations#schools_mass_operation'

  get '/all_devices' => 'organisations#all_devices'
  get '/get_all_devices' => 'organisations#get_all_devices'
  post '/devices_mass_operations' => 'devices_mass_operations#devices_mass_operation'

  post '/servers_mass_operations' => 'servers_mass_operations#servers_mass_operation'

  get '/all_images' => 'image_statistics#all_images'

  get '/all_users' => 'organisations#all_users'
  get '/get_all_users' => 'organisations#get_all_users'
  post '/users_mass_operations' => 'users_mass_operations#users_mass_operation'

  get '/all_groups' => 'organisations#all_groups'
  get '/get_all_groups' => 'organisations#get_all_groups'
  post '/groups_mass_operations' => 'groups_mass_operations#groups_mass_operation'

  get '/mfa_form' => 'sessions#mfa_ask', :as => :mfa_ask_code
  post '/mfa_form' => 'sessions#mfa_post', :as => :mfa_post_code

  # Organisation-level Puavomenu editor
  get '/puavomenu' => 'organisations#edit_puavomenu', :as => 'organisation_puavomenu'
  post '/puavomenu/save' => 'organisations#save_puavomenu', :as => 'organisation_puavomenu_save'
  delete '/puavomenu/clear' => 'organisations#clear_puavomenu', :as => 'organisation_puavomenu_clear'

  # On-the-fly UI language changing
  get '/change_language' => 'sessions#change_language'

  scope :path => "restproxy" do
    match '(*url)' => 'rest#proxy', :via => [:get, :post, :put], :format => false
  end

  scope :path => "users" do
    resources :ldap_services
    resource :organisation_external_services

    scope :path => ':school_id' do
      resource :rename_groups
    end

    namespace :schools do
      scope :path => ':school_id' do
        resource :external_services
      end
    end

    scope :path => ':school_id' do
      resources :printer_permissions
    end

    scope :path => ':school_id' do
      match 'lists' => 'lists#index', :as => :lists, :via => :get
      match 'lists/:id' => 'lists#download', :as => :download_list, :via => :post
      match 'lists/:id' => 'lists#download_as_csv', :as => :download_list_as_csv, :via => :get
      match 'lists/:id' => 'lists#delete', :as => :delete_list, :via => :delete
    end

    match 'schools/:id/admins' => 'schools#admins', :as => :admins_school, :via => :get
    match 'schools/:id/add_school_admin/:user_id' => 'schools#add_school_admin', :as => :add_school_admin_school, :via => :put
    match 'schools/:id/remove_school_admin/:user_id' => 'schools#remove_school_admin', :as => :remove_school_admin_school, :via => :put
    match 'schools/:id/wlan' => 'schools#wlan', :as => :wlan_school, :via => :get
    match 'schools/:id/wlan_update' => 'schools#wlan_update', :as => :wlan_update_school, :via => :patch
    match 'schools/:id/external_services' => 'external_services#index', :as => :external_services_school, :via => :get

    # School-level Puavomenu editor
    match 'schools/:id/puavomenu' => 'schools#edit_puavomenu', :as => 'school_puavomenu', :via => :get
    match 'schools/:id/puavomenu/save' => 'schools#save_puavomenu', :as => 'school_puavomenu_save', :via => :post
    match 'schools/:id/puavomenu/clear' => 'schools#clear_puavomenu', :as => 'school_puavomenu_clear', :via => :delete

    resources :schools

    scope :path => ':school_id' do
      match "groups/:id/remove_user/:user_id" => "groups#remove_user", :as => "remove_user_group", :via => :put
      match 'groups/:id/create_username_list_from_group' => 'groups#create_username_list_from_group', :as => "create_username_list_from_group", :via => :put
      match 'groups/:id/mark_group_members_for_deletion' => 'groups#mark_group_members_for_deletion', :as => "mark_group_members_for_deletion", :via => :put
      match 'groups/:id/unmark_group_members_deletion' => 'groups#unmark_group_members_deletion', :as => "unmark_group_members_deletion", :via => :put
      match 'groups/:id/lock_all_members' => 'groups#lock_all_members', :as => "lock_all_members", :via => :put
      match 'groups/:id/unlock_all_members' => 'groups#unlock_all_members', :as => "unlock_all_members", :via => :put
      match 'groups/:id/delete_all_group_members' => 'groups#delete_all_group_members', :as => "delete_all_group_members", :via => :delete
      match "groups/:id/add_user/:user_id" => "groups#add_user", :as => "add_user_group", :via => :put
      match "groups/:id/user_search" => "groups#user_search", :as => :user_search, :via => :get
      get 'groups/:id/select_new_school' => 'groups#select_new_school', :as => :select_new_school, :via => :get
      put 'groups/:id/change_school' => 'groups#change_school', :as => :group_change_school, :via => :put
      get 'groups/:id/get_members_as_csv' => 'groups#get_members_as_csv', :as => :get_members_as_csv
      put 'groups/:id/remove_all_members' => 'groups#remove_all_members', :as => :remove_all_members

      get 'get_school_groups_list' => 'groups#get_school_groups_list'

      get 'groups/members_mass_edit' => 'groups#members_mass_edit', :as => :group_members_mass_edit
      get 'groups/get_all_groups_members' => 'groups#get_all_groups_members'
      get 'groups/update_groups_list' => 'groups#update_groups_list'
      post 'groups/change_members' => 'groups#mass_op_change_members'

      get 'groups/find_groupless_users' => 'groups#find_groupless_users', :as => :find_groupless_users
      post 'groups/find_groupless_users' => 'groups#process_groupless_users', :as => :process_groupless_users

      get 'groups/:id/members' => 'groups#members'

      match 'users/:id/add_group' => 'users#add_group', :as => :add_group_user, :via => :put
      match 'username_redirect/:username' => 'users#username_redirect', :via => :get, :constraints => { :username => /[^\/]+/ }
      get 'users/:id/lock' => 'users#lock', :as => :lock_user
      get 'users/:id/unlock' => 'users#unlock', :as => :unlock_user
      match 'users/:id/mark_user_for_deletion' => 'users#mark_for_deletion', :as => :mark_user_for_deletion, :via => :get
      match 'users/:id/unmark_user_for_deletion' => 'users#unmark_for_deletion', :as => :unmark_user_for_deletion, :via => :get
      match 'users/:id/prevent_deletion' => 'users#prevent_deletion', :as => :prevent_deletion, :via => :get
      match 'users/:id/edit_admin_permissions' => 'users#edit_admin_permissions', :as => :edit_admin_permissions, :via => :get
      match 'users/:id/save_admin_permissions' => 'users#save_admin_permissions', :as => :save_admin_permissions, :via => :post
      match 'users/:id/edit_teacher_permissions' => 'users#edit_teacher_permissions', :as => :edit_teacher_permissions, :via => :get
      match 'users/:id/save_teacher_permissions' => 'users#save_teacher_permissions', :as => :save_teacher_permissions, :via => :post

      get 'users/:id/request_password_reset' => 'users#request_password_reset', :as => :request_password_reset
      get 'users/:id/reset_sso_session' => 'users#reset_sso_session', :as => :reset_sso_session

      match 'users/:id/change_schools' => 'users#change_schools', :as => :change_schools, :via => :get
      match 'users/:id/change_schools/add_school/:school' => 'users#add_to_school', :as => :add_user_to_school, :via => :get
      match 'users/:id/change_schools/remove_school/:school' => 'users#remove_from_school', :as => :remove_user_from_school, :via => :get
      match 'users/:id/change_schools/set_primary_school/:school' => 'users#set_primary_school', :as => :set_user_primary_school, :via => :get
      match 'users/:id/change_schools/add_and_set_primary_school/:school' => 'users#add_and_set_primary_school', :as => :add_and_set_user_primary_school, :via => :get
      match 'users/:id/change_schools/move_to_school/:school' => 'users#move_to_school', :as => :move_to_school, :via => :get

      get 'get_school_users_list' => 'users#get_school_users_list'

      get 'new_import' => 'new_import#index'
      get 'new_import/duplicate_detection' => 'new_import#duplicate_detection'
      get 'new_import/load_username_list' => 'new_import#load_username_list'
      get 'new_import/reload_groups' => 'new_import#reload_groups'
      post 'new_import/find_existing_users' => 'new_import#find_existing_users'
      post 'new_import/generate_pdf' => 'new_import#generate_pdf'
      post 'new_import/get_current_users' => 'new_import#get_current_users'
      post 'new_import/import' => 'new_import#import'
      post 'new_import/make_username_list' => 'new_import#make_username_list'
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

    get '/login' => 'sessions#new', :as => :login
    post '/login' => 'sessions#create'
    match '/logout' => 'sessions#destroy', :as => :logout, :via => :delete

    resources :sessions
    get 'schools/:id/image' => 'schools#image', :as => :image_school
    get '/' => 'schools#index'

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
      get( 'successfully',
           :to => 'password#successfully',
           :as => :successfully_password )
    end

    get 'themes/:theme' => 'themes#set_theme', :as => :set_theme
    resources :admins

    match 'owners' => 'organisations#owners', :as => :owners_organisation, :via => :get
    match 'remove_owner/:user_id' => 'organisations#remove_owner', :as => :remove_owner_organisations, :via => :put
    match 'add_owner/:user_id' => 'organisations#add_owner', :as => :add_owner_organisations, :via => :put

    match 'all_admins' => 'organisations#all_admins', :as => :all_admins_organisation, :via => :get
    post 'all_admins_mass_operations' => 'admin_permissions_mass_operations#admin_permissions_mass_operation'

    match 'wlan' => 'organisations#wlan', :as => :wlan_organisation, :via => :get
    match 'wlan_update' => 'organisations#wlan_update', :as => :wlan_update_organisation, :via => :patch

    resource :organisation, :only => [:show, :edit, :update]
    resource :profile, :only => [:edit, :update, :show]
    get "profile/image" => "profiles#image", :as => :image_profile
    post 'profile/send_verification_email' => 'profiles#send_verification_email', :as => :profile_send_verification_email

    get('email_verification/:token', to: 'email_verifications#edit', as: :email_verification, constraints: { token: /[0-9a-fA-F]{128}/ })
    post('email_verification/:token', to: 'email_verifications#update', as: :email_verification_update, constraints: { token: /[0-9a-fA-F]{128}/ })
    get 'email_verification/complete' => 'email_verifications#complete', :as => :email_verification_completed

    # The MFA editor
    resource :mfa, only: [:show]
    post 'mfa/prepare_totp' => 'mfas#prepare_totp', as: :mfa_prepare_totp
    post 'mfa/verify' => 'mfas#verify', as: :mfa_verify
    match 'mfa/delete' => 'mfas#delete', as: :mfa_delete, via: :delete
    get 'mfa/list_recovery_keys' => 'mfas#list_recovery_keys', as: :mfa_list_recovery_keys
    post 'mfa/create_recovery_keys' => 'mfas#create_recovery_keys', as: :mfa_create_recovery_keys
    delete 'mfa/delete_recovery_keys' => 'mfas#delete_recovery_keys', as: :mfa_delete_recovery_keys
  end

  scope :path => "devices" do
    get '/' => 'schools#index'

    match 'sessions/show' => 'api/v1/sessions#show', :via => :get
    resources :sessions

    get 'hosts/types' => 'hosts#types'

    scope :path => ':school_id' do
      match 'devices/:id/select_school' => 'devices#select_school', :as => 'select_school_device', :via => :get
      match 'devices/:id/change_school' => 'devices#change_school', :as => 'change_school_device', :via => :post
      match 'devices/:id/image' => 'devices#image', :as => 'image_device', :via => :get
      match 'devices/:id/raw_hardware_info' => 'devices#raw_hardware_info', :as => 'device_raw_hardware_info', :via => :get

      # Device-level Puavomenu editor
      match 'devices/:id/puavomenu' => 'devices#edit_puavomenu', :as => 'device_puavomenu', :via => :get
      match 'devices/:id/puavomenu/save' => 'devices#save_puavomenu', :as => 'device_puavomenu_save', :via => :post
      match 'devices/:id/puavomenu/clear' => 'devices#clear_puavomenu', :as => 'device_puavomenu_clear', :via => :delete

      get 'devices/device_statistics' => 'image_statistics#school_images', :as => 'school_image_statistics'

      get 'get_school_devices_list' => 'devices#get_school_devices_list'

      post 'mass_op_device_change_school' => 'devices#mass_op_device_change_school'
      post 'mass_op_device_delete' => 'devices#mass_op_device_delete'
      post 'mass_op_device_set_image' => 'devices#mass_op_device_set_image'
      post 'mass_op_device_set_field' => 'devices#mass_op_device_set_field'
      post 'mass_op_device_edit_puavoconf' => 'devices#mass_op_device_edit_puavoconf'
      post 'mass_op_device_purchase_info' => 'devices#mass_op_device_purchase_info'
      post 'mass_op_device_reset' => 'devices#mass_op_device_reset'

      resources :devices

      match( 'devices/:id/revoke_certificate' => 'devices#revoke_certificate',
             :as => 'revoke_certificate_device',
             :via => :delete )

      match( 'devices/:id/set_reset_mode' => 'devices#set_reset_mode',
             :as => 'set_reset_mode_device',
             :via => :put )

      match( 'devices/:id/clear_reset_mode' => 'devices#clear_reset_mode',
             :as => 'clear_reset_mode_device',
             :via => :put )
    end

    match 'servers/:id/image' => 'servers#image', :as => 'image_server', :via => :get
    match 'servers/:id/raw_hardware_info' => 'servers#raw_hardware_info', :as => 'server_raw_hardware_info', :via => :get
    match( 'servers/:id/revoke_certificate' => 'servers#revoke_certificate',
           :as => 'revoke_certificate_server',
           :via => :delete )
    resources :servers

    get 'get_servers_list' => 'servers#get_servers_list'

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

  ["", "api/v2/"].each do |prefix|
    new_prefix = prefix.gsub("/", "_")
    match("#{ prefix }external_files" => "external_files#index", :via => :get)
    match("#{ prefix }external_files" => "external_files#upload", :via => :post)
    match(
      "#{ prefix }external_files/:name" => "external_files#get_file",
      :name => /.+/,
      :format => false,
      :via => :get,
      :as => "#{new_prefix}download_external_file"
    )
    match(
      "#{ prefix }external_files/:name" => "external_files#destroy",
      :name => /.+/,
      :format => false,
      :via => :delete,
      :as => "#{new_prefix}destroy_external_file"
    )
  end

  # Final catch-all route, 404 everything from this point on
  if ENV["RAILS_ENV"] == "production"
    match "*path", to: "application#send_404", via: :all
  end

end
