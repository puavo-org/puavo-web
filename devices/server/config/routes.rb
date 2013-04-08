ActionController::Routing::Routes.draw do |map|
  map.resources :sessions

  map.resources :hosts, :only => [:index], :collection => { :types => :get }

  map.select_school_device( 'devices/:id/select_school',
                            :controller => 'devices',
                            :action => 'select_school',
                            :path_prefix => ':school_id',
                            :conditions => { :method => :get } )
  map.change_school_device( 'devices/:id/change_school',
                            :controller => 'devices',
                            :action => 'change_school',
                            :path_prefix => ':school_id',
                            :conditions => { :method => :post } )
  map.image_device( 'devices/:id/image',
                      :controller => 'devices',
                      :action => 'image',
                      :path_prefix => ':school_id',
                      :conditions => { :method => :get } )

  map.namespace :api do |api| 
    api.namespace :v2 do |v2| 
      v2.resources :devices
      v2.resources :servers
    end
  end

  map.organisation_devices( 'devices.:format',
                            :controller => 'devices',
                            :action => 'index',
                            :conditions => { :method => :get } )

  map.resources :devices, :path_prefix => ':school_id'


  map.revoke_certificate_device '/devices/:id/revoke_certificate', :controller => 'devices', :action => 'revoke_certificate', :conditions => { :method => :delete }, :path_prefix => ':school_id'

  map.image_server( 'servers/:id/image',
                      :controller => 'servers',
                      :action => 'image',
                      :conditions => { :method => :get } )
  map.resources :servers, :has_many => :automounts
  map.revoke_certificate_server '/servers/:id/revoke_certificate', :controller => 'servers', :action => 'revoke_certificate', :conditions => { :method => :delete }

  map.resources :printers, :except => [:show, :new]

  map.login '/login', :controller => 'sessions', :action => 'new'
  map.logout '/logout', :controller => 'sessions', :action => 'destroy'

  map.auth( '/auth.:format',
            :controller => 'sessions',
            :action => 'auth',
            :method => :get )
  
  map.resources :search, :only => [:index]

  # The priority is based upon order of creation: first created -> highest priority.

  # Sample of regular route:
  #   map.connect 'products/:id', :controller => 'catalog', :action => 'view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   map.purchase 'products/:id/purchase', :controller => 'catalog', :action => 'purchase'
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   map.resources :products

  # Sample resource route with options:
  #   map.resources :products, :member => { :short => :get, :toggle => :post }, :collection => { :sold => :get }

  # Sample resource route with sub-resources:
  #   map.resources :products, :has_many => [ :comments, :sales ], :has_one => :seller

  # Sample resource route with more complex sub-resources
  #   map.resources :products do |products|
  #     products.resources :comments
  #     products.resources :sales, :collection => { :recent => :get }
  #   end

  # Sample resource route within a namespace:
  #   map.namespace :admin do |admin|
  #     # Directs /admin/products/* to Admin::ProductsController (app/controllers/admin/products_controller.rb)
  #     admin.resources :products
  #   end

  # You can have the root of your site routed with map.root -- just remember to delete public/index.html.
  # map.root :controller => "welcome"
  map.root :controller => "servers"

  # See how all your routes lay out with "rake routes"

  # Install the default routes as the lowest priority.
  # Note: These default routes make all actions in every controller accessible via GET requests. You should
  # consider removing or commenting them out if you're using named routes and resources.
  map.connect ':controller/:action/:id'
  map.connect ':controller/:action/:id.:format'
end
