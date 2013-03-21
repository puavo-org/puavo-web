# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def label(object_name, method, human_name, content, *args)

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
end
