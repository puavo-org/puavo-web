module RenameGroupsHelper

  def increase_numeric_value_of_string(value)
    match_data = value.match(/\d+/)
    number_length = match_data[0].length
    number = match_data[0].to_i + 1
    return value.sub(/\d+/, ("%0#{number_length}d" % number))
  end
end
