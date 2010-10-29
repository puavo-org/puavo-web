# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def label(*args)
    # Using value by localize if found it
    # 
    # Model key name
    attribute_translate_name = translate_name_attribute(args[0], args[1])
    # Using humanize method by String class If args[2] is nil
    args[2] = attribute_translate_name unless attribute_translate_name.nil?

    # Add lable_error class to fiel element if object is invalid
    if args[3] && args[3][:object] && args[3][:object].errors.invalid?(args[1])
      args[3][:class] = 'label_error'
    end
    super(*args)
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

  def field_error_text(object, method)
    if object.errors.invalid?(method)
      error_message = Array(object.errors.on(method)).first
      if error_message.match(/is required attribute by objectClass/)
        error_message = translate_error(object, method)
      end
      content_tag(:span, error_message, :class => 'field_error')
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
end
