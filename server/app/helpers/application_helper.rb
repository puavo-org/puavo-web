# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def label(*args)
    # Using value by localize if found it
    #
    # Model key name
    if I18n.t("activeldap.attributes").has_key?(args[0].to_sym) &&
        # Attribute key name
        I18n.t("activeldap.attributes.#{args[0]}").key?(args[1].to_sym)
      # Using humanize method by String class If args[2] is nil
      args[2] = I18n.t("activeldap.attributes.#{args[0]}.#{args[1]}")
    end
    super(*args)
  end

  def text_field(*args)
    begin
      if args[2][:object][args[1]].class == Array
        args[2][:object][args[1]] = args[2][:object][args[1]].join(" ")
      end
    rescue
      nil
    end
    super(*args)
  end
end
