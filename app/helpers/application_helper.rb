# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  include Puavo::Helpers


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

  def text_field(*args)
    after_html = field_error_text(args[2][:object], args[1]) if ! args[2].nil? && ! args[2][:object].nil?
    super(*args) + after_html.to_s
  end

  def password_field(*args)
    after_html = field_error_text(args[2][:object], args[1]) if ! args[2].nil? && ! args[2][:object].nil?
    super(*args) + after_html.to_s
  end

  def select(*args)
    after_html = field_error_text(args[3][:object], args[1]) if ! args[3].nil? && ! args[3][:object].nil?
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
  def debug_footer
    "
    <footer class=debug style='color: transparent; font-size: small; text-align: right'>
      hostname: #{ Socket.gethostname },
      version: #{ PuavoUsers::VERSION },
      git commit: #{ PuavoUsers::GIT_COMMIT },
      deb package: #{ DEB_PACKAGE },
      uptime: #{ (Time.now - STARTED).to_i } sec
    </footer>
    ".html_safe
  end

  def group_types_for_select
    ['teaching group', 'year class', 'administrative group', 'other'].map do |type|
      [t('group_type.' + type), type]
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
    default =  "Europe/Helsinki"
    default = value if value
    options_for_select(options, default)
  end

  def humanize_timezone(zone)
    timezones = ActiveSupport::TimeZone::MAPPING.invert
    return I18n.t("timezone_empty") if timezones[zone].nil?

    ActiveSupport::TimeZone[ timezones[zone] ].to_s
  end

  def link_to_user_by_dn(dn)
    return "" if dn.nil?

    return "" if dn.class != ActiveLdap::DistinguishedName

    begin
      user = User.find(dn)
    rescue ActiveLdap::EntryNotFound
      return ""
    end

    return link_to( user.displayName, user_path(:school_id => user.school.puavoId, :id => user.puavoId) )

  end

  def uid_by_dn(dn)
    return "" if dn.nil?

    return "" if dn.class != ActiveLdap::DistinguishedName

    begin
      user_uid = User.find(dn).uid
    rescue ActiveLdap::EntryNotFound
      user_uid = ""
    end

    return user_uid
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
        content = "<input name='#{object_name}[#{attribute}][]' size='30' type='text' />"
      else
	Array(model.send(attribute)).each do |value|
          content += "<input name='#{object_name}[#{attribute}][]' size='30' type='text' value='#{value}' />"
	end
      end
      content.html_safe
    end +

    link_to("#", :class => "clone_prev_input_element btn") do
      content_tag(:i, link_text, :class => "icon-plus")
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
end
