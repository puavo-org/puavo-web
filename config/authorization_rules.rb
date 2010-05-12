authorization do
  role :superuser do
    has_permission_on [:organisations, :schools, :groups, :users], :to => :manage
  end

  role :organisation_admin do
    has_permission_on [:access, :organisations, :schools, :groups, :users], :to => :manage do
      if_attribute :organisation_id => is {user.organisation.id }
    end
  end

  role :school_admin do
    has_permission_on :schools, :to => [:read, :update] do
      if_attribute :school_id =>  is_in {  user.admin_in_schools }
    end
  end

  role :users_admin do
    has_permission_on [:group, :users], :to => :manage do
      if_attribute :school_id =>  is_in {  user.admin_in_schools }
    end
    # Before create object school_id is nil (new action)
    has_permission_on [:group, :users], :to => :create do
      if_attribute :school_id =>  is { nil }
    end
    has_permission_on [:users_import], :to => [:new, :validate, :refine, :group, :preview, :create, :show]
  end

  role :guest do
    has_permission_on :users, :to => [:read, :update] do
      #if_attribute :id => is { user.id }
    end
    has_permission_on :password, :to => :update
  end
end

privileges do
  privilege :manage, :includes => [:create, :read, :update, :delete]
  privilege :read, :includes => [:index, :show]
  privilege :create, :includes => :new
  privilege :update, :includes => :edit
  privilege :delete, :includes => :destroy
end
