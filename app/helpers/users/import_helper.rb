module Users::ImportHelper

  def invalid_user_field(user, user_index, column, column_index)
    error_message = field_error_text(user, column)

    case column
    when "role_ids"
      html = select_tag( "users_import_invalid_list[#{column_index}][]", 
              options_for_select( Role.all.collect{ |g| [g.displayName, g.puavoId] }) )
    else
      html = text_field_tag( "users_import_invalid_list[#{column_index}][]",
                             user.human_readable_format(column),
                             :id => "users_import_invalid_list_#{column_index}_#{user_index}",
                             :class => (error_message.nil? ? "" : "field_value_error" ) )
    end

    return html + error_message.to_s
  end
end
