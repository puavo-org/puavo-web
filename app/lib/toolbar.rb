# A small DSL system for toolbars, links and dropdowns on list, show and edit pages

class Toolbar
  # Internal drop-down menu builder class. Adds links and separators to a menu.
  class Menu
    attr_reader :entries

    def initialize
      @separator_pending = false
      @entries = []
    end

    # TODO: Can this and the (almost identical) method in the parent class be merged?
    def link(title, enabled: true, href: nil, icon: nil, confirm: nil, method: nil, danger: false, owners: false)
      # The first and last menu entries won't be a separator
      @entries << { type: :separator } if @separator_pending && !@entries.empty?

      @entries << {
        type: :link,
        title: title,
        icon: icon,
        href: href,
        owners: owners,
        confirm: confirm,
        method: method,
        danger: danger,
        enabled: enabled
      }

      @separator_pending = false
    end

    def separator
      return if @entries.empty?

      # Coalesce multiple consecutive separators
      @separator_pending = true
    end
  end

  def initialize
    @entries = []
  end

  # TODO: Clean up this mess
  def _emit_link(e, in_menu: false)
    classes = []

    unless in_menu
      classes << 'btn'
      classes << 'btn-danger' if e[:danger]
    end

    classes << 'ownersOnly' if e[:owners]
    classes << 'noIcon' unless e[:icon]

    out = '<li><a'
    out += " class=\"#{classes.join(' ')}\"" unless classes.empty?
    out += " href=\"#{e[:href]}\""

    if e[:confirm]
      out += " data-confirm=\"#{e[:confirm]}\""
    end

    if e[:method]
      out += " data-method=\"#{e[:method]}\" rel=\"nofollow\""
    end

    out += '>'
    out += "<i class=\"icon-#{e[:icon]}\"></i>" if e[:icon]
    out += e[:title]
    out += "</a></li>\n"

    out
  end

  def build(&block)
    # Generate the entries
    block.call(self) if block
    return if @entries.empty?

    # Turn the entries into HTML
    code = ''

    @entries.each do |tb_e|
      case tb_e[:type]
        when :link
          code << _emit_link(tb_e)

        when :menu
          # Completely hide the menu if it's empty
          next if tb_e[:entries].nil? || tb_e[:entries].empty?

          code << "<li class=\"haveDropdown2\"><span class=\"btn\"><i class=\"icon-collapse\"></i>#{tb_e[:title]}</span>\n"

          cls = ['dropdown2']
          cls << 'dropRight2' if tb_e[:right]

          code << "<ul class=\"#{cls.join(' ')}\">\n"

          tb_e[:entries].each do |m_e|
            case m_e[:type]
              when :separator
                code << "<li class=\"separator\"></li>\n"

              when :link
                code << _emit_link(m_e, in_menu: true)
            end
          end

          code << "</ul></li>\n"
      end
    end

    code.html_safe
  end

  # Adds a link to the toolbar
  def link(title, enabled: true, href: nil, icon: nil, confirm: nil, method: nil, danger: false, owners: false)
    @entries << {
      type: :link,
      title: title,
      href: href,
      icon: icon,
      enabled: enabled,
      confirm: confirm,
      method: method,
      danger: danger,
      owners: owners,
    }
  end

  # Adds a dropdown menu
  def dropdown(title, right: false, &block)
    menu = Menu.new

    block.call(menu)

    if menu.entries.empty?
      @entries << {
        type: :menu,
        title: title,
        right: right,
        enabled: false
      }
    else
      @entries << {
        type: :menu,
        title: title,
        enabled: true,
        right: right,
        entries: menu.entries
      }
    end
  end
end
