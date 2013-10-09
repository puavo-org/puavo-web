class MetaMenu

  @@store = {}

  def self.store
    @@store[self] ||= {
      :controller_names => Set.new,
      :action_names => Set.new,
      :children => []
    }
  end

  def store
    self.class.store
  end

  def initialize(controller, parent=nil)
    @controller = controller
    @school = controller.school
    @parent = parent
  end


  [:hide_when, :link, :title].each do |method_name|
    define_singleton_method method_name do |&block|
      store[method_name] = block
    end
    define_method method_name do
      @controller.instance_exec(&store[method_name])
    end
  end

  def hide?
    hide_when if store[:hide_when]
  end

  def self.active_on(*controllers)
    store[:controller_names].merge(controllers.map{|c| c.controller_name })
  end

  def self.active_on_action(*action_names)
    store[:action_names].merge(action_names)
  end


  def children
    store[:children].map { |c| c.new(@controller) }
  end

  def active?
    # Child menu cannot be active if parent is not
    if @parent && !@parent.active?
      return false
    end

    if !store[:controller_names].empty?
      if !store[:controller_names].include?(@controller.controller_name)
        return false
      end
    end

    if !store[:action_names].empty?
      if !store[:action_names].include?(@controller.action_name)
        return false
      end
    end

    return true
  end

  def self.child(&class_definition)
    store[:children].append(Class.new(MetaMenu, &class_definition))
  end

end
