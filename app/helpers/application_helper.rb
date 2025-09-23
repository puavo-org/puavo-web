require 'toolbar'

# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  include Puavo::Helpers
  include Puavo::Integrations

  # FIXME: see code from Github: https://github.com/opinsys/puavo-view-helpers
  def label(object_name, method, human_name=nil, content=nil, *args)

    # If we don't get human name from the label get use the string from translation
    human_name ||= translate_name_attribute(object_name, method)

    # Add CSS class 'label_error' to field element if object is invalid
    if content && content[:object] && !content[:object].errors[method].empty?
      (content[:class] ||= []).push "label_error"
    end
    super(object_name, method, human_name, content, *args)
  end

  def text_area(*args)
    after_html = field_error_text_span(args[2][:object], args[1]) if ! args[2].nil? && ! args[2][:object].nil?
    super(*args) + after_html.to_s
  end

  def text_field(*args)
    after_html = field_error_text_span(args[2][:object], args[1]) if ! args[2].nil? && ! args[2][:object].nil?
    super(*args) + after_html.to_s
  end

  def password_field(*args)
    after_html = field_error_text_span(args[2][:object], args[1]) if ! args[2].nil? && ! args[2][:object].nil?
    super(*args) + after_html.to_s
  end

  def select(*args)
    after_html = field_error_text_span(args[3][:object], args[1]) if ! args[3].nil? && ! args[3][:object].nil?
    super(*args) + after_html.to_s
  end

  def file_field(*args)
    after_html = field_error_text_span(args[2][:object], args[1]) if ! args[2].nil? && ! args[2][:object].nil?
    super(*args) + after_html.to_s
  end

  def field_error_text_span(object, method)
    content_tag(:span, field_error_text(object, method), :class => 'field_error')
  end

  def field_error_text(object, method)
    if !object.errors[method].empty?
      error_message = Array(object.errors[method]).first
      if error_message && error_message.match(/is required attribute by objectClass/)
        error_message = translate_error(object, method)
      end
      error_message
    end
  end

  def translate_error(object, method)
    I18n.t("activeldap.errors.messages.blank", :attribute => translate_name_attribute(object.class.to_s.downcase, method) )
  end

  # Using value by localize if found it
  #
  # Model key name
  def translate_name_attribute(model, attribute)
    if I18n.t("activeldap.attributes").has_key?(model.to_sym) &&
        # Attribute key name
        I18n.t("activeldap.attributes.#{model}").key?(attribute.to_sym)
      return I18n.t("activeldap.attributes.#{model}.#{attribute}")
    end
  end

  def translate_boolean_value(value)
    case value
    when true
      return I18n.t("helpers.boolean_true")
    when false
      return I18n.t("helpers.boolean_false")
    else
      return I18n.t("helpers.default")
    end
  end


  STARTED = Time.now
  DEB_PACKAGE = Array(`dpkg -l | grep puavo-web`.split())[2]

  def debug_footer(reduced: false)
    if reduced
      "Hostname: #{ Socket.gethostname }".html_safe
    else
      "Hostname: #{ Socket.gethostname } Uptime: #{ (Time.now - STARTED).to_i } seconds<br>Commit: #{ PuavoUsers::GIT_COMMIT }".html_safe
    end
  end

  def group_types_for_select
    [[t("default_select_value"), ""]] +
    (['teaching group', 'course group', 'year class', 'administrative group', 'archive users', 'other groups']).map do |type|
      [humanize_group_type(type), type]
    end
  end

  def locales_for_select
    for_select = []
    for_select.push([t('language_default'), ""])
    Puavo::CONFIG["locales"].each do |locale|
      language, character_encoding = locale.split(".")
      for_select.push( [t("language_#{language}"), language + ".UTF-8"] )
     end
    return for_select
  end

  def language_by_locale(locale)
    return t("language_default") if not locale

    language = locale.split(".").first
    t("language_#{language}")
  end

  def timezones_for_select(value)
    options = ActiveSupport::TimeZone.all.map do |zone|
      [zone.to_s, ActiveSupport::TimeZone::MAPPING[zone.name]]
    end

    options.unshift([t('timezone_leave_unset'), nil])

    default = nil
    default = value if value
    options_for_select(options, default)
  end

  def humanize_timezone(zone)
    timezones = ActiveSupport::TimeZone::MAPPING.invert
    return I18n.t("timezone_empty") if timezones[zone].nil?

    ActiveSupport::TimeZone[ timezones[zone] ].to_s
  end

  def humanize_group_type(group_type)
    return "" unless group_type

    t('group_type.' + group_type)
  end

  def find_user_by_dn(dn)
    return nil if dn.nil?

    return nil if dn.class != ActiveLdap::DistinguishedName

    begin
      return User.find(dn)
    rescue ActiveLdap::EntryNotFound
      return nil
    end
  end

  def link_to_user_by_dn(dn)
    user = find_user_by_dn(dn)
    return "<span class=\"missingData\">#{dn.to_s}</span>".html_safe unless user
    return link_to("#{user.displayName}",
                   user_path(:school_id => user.primary_school.puavoId,
                             :id => user.puavoId))
  end

  def get_uid_by_dn(dn)
    user = find_user_by_dn(dn)
    return user ? user.uid : ''
  end

  def fingerprint(public_key)
    if public_key
      begin
        SSHKey.fingerprint public_key
      rescue SSHKey::PublicKeyError
        return I18n.t("helpers.invalid_ssh_public_key")
      end
    end
  end

  def default_value_by_parent(model, attribute)
    label = nil
    parent_path = nil
    value = nil

    if model.parent.class == School
      unless model.parent.send(attribute).nil?
        label = I18n.t("helpers.default_by_school") + ":"
        parent_path = edit_school_path(model.parent)
        value = model.parent.send(attribute)
      end
    end

    if label.nil?
      label = I18n.t("helpers.default_by_organisation") + ":"
      parent_path = edit_organisation_path
      value = LdapOrganisation.current.send(attribute)
    end

    return if value.nil?

    if value.is_a?(Array)
      value = value.join(", ")
    end

    value = truncate(value, :length => 60)

    return content_tag(:b, label) + " " +
      value.to_s + " " +
      link_to(I18n.t("link.edit"), parent_path)

  end

  def value_or_default_value_by_parent(model, attribute)
    value = model.send(attribute)
    suffix = ""

    if value.nil?
      if model.parent.class == School
        value = model.parent.send(attribute)
        suffix = I18n.t("helpers.by_school")
      end

      if value.nil?
        value = LdapOrganisation.current.send(attribute)
        suffix = I18n.t("helpers.by_organisation")
      end
    end

    suffix = "" if value.nil?


    return multiple_value(value) + " " + suffix
  end

  def multiple_text_field(model, attribute, link_text)
    object_name = ActiveModel::Naming.param_key(model)

    content_tag(:div, :id => "#{object_name}_#{attribute}") do
      content = ""
      if model.send(attribute).nil?
        content = "<input id='#{attribute}0' name='#{object_name}[#{attribute}][]' size='30' type='text' />"
      else
        Array(model.send(attribute)).each_with_index do |value, index|
          content += "<input id='#{attribute}#{index}' name='#{object_name}[#{attribute}][]' size='30' type='text' value='#{value}' />"
        end
      end
      content.html_safe
    end +

    link_to("#", :class => "clone_prev_input_element btn") do
      content_tag(:i, "", :class => "icon-plus") +
      link_text
    end +

    content_tag(:div, field_error_text(model, attribute))

  end

  def multiple_value(values)
    Array(values).map do |value|
      content_tag(:div, value)
    end.join("\n").html_safe
  end

  def group_member?(group, user)
    group["member_usernames"].include?(user.uid)
  end

  def page_title(*parts)
    content_for(:page_title, parts.unshift(LdapOrganisation.current.o).join(' / '))
  end

  def start_box(title, extraClass="")
    "<div class=\"contentBox #{extraClass}\"><header>#{title}</header><div class=\"contents\">".html_safe
  end

  def end_box
    "</div></div>".html_safe
  end

  def value_or_default(v, default)
    (v.nil? ? default : v).html_safe
  end

  def list_user_roles(roles)
    (Array(roles || []).collect { |r| t('puavoEduPersonAffiliation_' + r)}).join(', ').html_safe
  end

  def insert_wbr(s)
    (s.split('-').join('-<wbr>')).html_safe
  end

  def sortable_list_column_header(s)
    "<div><span class=\"name\">#{s}</span><span class=\"arrow\"></span></div>".html_safe
  end

  def get_puavoconf_definitions
    # If the puavo-conf definitions file exists, load it. Otherwise the puavo-conf
    # editor will not offer suggestions. The definitions file does not exist by default,
    # but it can be generated by taking the puavo-conf listing from any recent image
    # series JSON, then placing it in the configuration directory (a symlink is good).
    begin
      defs = File.read("#{Rails.root}/config/puavoconf_definitions.json")
    rescue
      defs = '{}'
    end

    return defs.html_safe
  end

  def format_uptime(seconds)
    return '?' unless seconds.is_a?(Integer)

    parts = []

    # Days
    if seconds >= 86400
      d = (seconds / 86400).to_i
      parts << "#{d}d"
      seconds -= d * 86400
    end

    # Hours
    if seconds >= 3600
      h = (seconds / 3600).to_i
      parts << "#{h}h"
      seconds -= h * 3600
    end

    # Minutes
    if seconds >= 60
      m = (seconds / 60).to_i
      parts << "#{m}m"
      seconds -= m * 60
    end

    # Seconds (avoid adding "0s" to the end, unless there are no other parts)
    if seconds > 0 || parts.empty?
      parts << "#{seconds}s"
    end

    parts.join(' ')
  end

  def format_notes(notes)
    notes.nil? ? nil : h(notes).gsub("\r", '').gsub("\n", '<br>').html_safe
  end

  def expiration_time_presets
    hour = 60 * 60
    day = hour * 24
    week = day * 7
    month = day * 30
    year = day * 365

    out = []

    [
      [ hour,       t('expiration_times.one_hour') ],
      [ hour * 6,   t('expiration_times.six_hours') ],
      [ hour * 12,  t('expiration_times.twelve_hours') ],
      [ day,        t('expiration_times.one_day') ],
      [ day * 2,    t('expiration_times.two_days') ],
      [ day * 3,    t('expiration_times.three_days') ],
      [ week,       t('expiration_times.one_week') ],
      [ week * 2,   t('expiration_times.two_weeks') ],
      [ week * 3,   t('expiration_times.three_weeks') ],
      [ month,      t('expiration_times.one_month') ],
      [ month * 2,  t('expiration_times.two_months') ],
      [ month * 3,  t('expiration_times.three_months') ],
      [ month * 6,  t('expiration_times.six_months') ],
      [ month * 9,  t('expiration_times.nine_months') ],
      [ year,       t('expiration_times.one_year') ],
      [ year * 3,   t('expiration_times.three_years') ],
    ].each do |p|
      out << "<option value=\"#{p[0]}\">#{p[1]}</option>"
    end

    out.join("\n").html_safe
  end

  def copyright
    Puavo::CONFIG.fetch('branding', {}).fetch('copyright', '(Unknown copyright)')
  end

  def copyright_year
    Puavo::CONFIG.fetch('branding', {}).fetch('copyright_year', '(Unknown copyright year)')
  end

  def copyright_with_year
    Puavo::CONFIG.fetch('branding', {}).fetch('copyright_with_year', '(Unknown copyright)')
  end

  def manufacturer_name
    Puavo::CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('name', '?')
  end

  def manufacturer_logo
    manufacturer = Puavo::CONFIG.fetch('branding', {}).fetch('manufacturer', {})
    return '' if manufacturer.empty?

    "<a href=\"#{manufacturer['url']}\" target=\"_blank\"><img src=\"#{manufacturer['logo']}\" alt=\"#{manufacturer['alt_text']}\" title=\"#{manufacturer['title']}\" width=\"#{manufacturer['logo_width']}\" height=\"#{manufacturer['logo_height']}\"></a>".html_safe
  end

  def technical_support_email
    Puavo::CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('technical_support_email', '?')
  end

  def technical_support_phone(international: false)
    phone = Puavo::CONFIG.fetch('branding', {}).fetch('manufacturer', {}).fetch('technical_support_phone', {})
    return '' if phone.empty?

    phone.fetch(international ? 'international' : 'short', '?')
  end

  # Wrapper
  def toolbar(&block)
    Toolbar.new.build(&block)
  end
end
