module Users::ImportHelper

  def user_list_editable_item(user, user_index, column, column_index)
    error_message = field_error_text_span(user, column)
    
    css_classes = "edit"
    css_classes += user.errors.invalid?(column) ? " invalid" : ""

    html = content_tag :div, :class => css_classes, :id => column_index do
      user.human_readable_format(column)
    end
    html += hidden_field_tag( "users[#{column_index}][]",
                              user.human_readable_format(column),
                              { :id => "users_#{column_index}_#{user_index}",
                                :class => "#{column}"} )
    return html + error_message.to_s
  end

  def invalid_user_field(user, user_index, column, column_index)
    error_message = field_error_text_span(user, column)

    case column
    when "role_ids"
      html = select_tag( "users_import_invalid_list[#{column_index}][]", 
                                               role_options_for_select( @roles, user.role_ids.first.to_s),
                                               :id => "users_import_invalid_list_#{column_index}_#{user_index}" )
    else
      html = text_field_tag( "users_import_invalid_list[#{column_index}][]",
                             user.human_readable_format(column),
                             :id => "users_import_invalid_list_#{column_index}_#{user_index}",
                             :class => (error_message.nil? ? "" : "field_value_error" ) )
    end

    return html + error_message.to_s
  end

  def role_options_for_select(roles, selected)
    roles.map do |role|
      "<option#{ role.puavoId.to_i == selected.to_i ? ' selected="selected"' : '' } value=\"#{role.puavoId}\">#{role.displayName}</options>"
    end.join("\n")
  end
end
