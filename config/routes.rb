PuavoUsers::Application.routes.draw do
  resource :rename_groups
  resources :external_services
  match 'roles/:id/select_school' => 'roles#select_school', :as => :select_school_role, :path_prefix => ':school_id', :via => :get
  match 'roles/:id/select_role' => 'roles#select_role', :as => :select_role_role, :path_prefix => ':school_id', :via => :post
  match 'roles/:id/add_group/:group_id' => 'roles#add_group', :as => :add_group_role, :path_prefix => ':school_id', :via => :put
  match 'roles/:id/remove_group/:group_id' => 'roles#remove_group', :as => :remove_group_role, :path_prefix => ':school_id', :via => :put
  resources :roles
  match 'schools/:id/admins.:format' => 'schools#admins', :as => :admins_school, :via => :get
  match 'schools/:id/add_school_admin/:user_id.:format' => 'schools#add_school_admin', :as => :add_school_admin_school, :via => :put
  match 'schools/:id/remove_school_admin/:user_id.:format' => 'schools#remove_school_admin', :as => :remove_school_admin_school, :via => :put
  resources :schools
  match 'groups/:id/members.:format' => 'groups#members', :as => :add_role_group, :path_prefix => ':school_id', :via => :get
  match 'groups/:id/add_role/:role_id' => 'groups#add_role', :as => :add_role_group, :path_prefix => ':school_id', :via => :put
  match 'groups/:id/delete_role/:role_id' => 'groups#delete_role', :as => :delete_role_group, :path_prefix => ':school_id', :via => :put
  match 'users/:id/select_school' => 'users#select_school', :as => :select_school_user, :path_prefix => ':school_id', :via => :get
  match 'users/:id/select_role' => 'users#select_role', :as => :select_role_user, :path_prefix => ':school_id', :via => :post
  match 'users/change_school' => 'users#change_school', :as => :change_school_users, :path_prefix => ':school_id', :via => :post
  resources :users
  match 'users/:id/image' => 'users#image', :as => :image_user, :path_prefix => ':school_id', :via => :get
  resources :users
  resources :groups
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
  match ':school_id/users/import/user_validate.:format' => 'users/import#user_validate', :as => :user_validate_users_import, :via => :post
  match ':school_id/users/import/options.:format' => 'users/import#options', :as => :options_users_import, :via => :get
  match ':school_id/users/import/download.:format' => 'users/import#download', :as => :download_users_import, :via => :get
  match 'password' => 'password#edit', :as => :password, :via => :get
  match 'password/edit' => 'password#edit', :as => :edit_password, :via => :get
  match 'password/own' => 'password#own', :as => :own_password, :via => :get
  match 'password' => 'password#update', :via => :put
  match 'themes/:theme' => 'themes#set_theme', :as => :set_theme
  resources :admins
  resource :organisation, :only => [:show, :edit, :update]
  resources :search, :only => [:index]
  resource :profile, :only => [:edit, :update, :show]
end
