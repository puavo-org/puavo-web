Given /^I send to the following user mass import data$/ do |raw_data|
  Given "I am on the new user import page"
  When "I fill in textarea \"raw_users\" with \"#{raw_data}\""
  And "I press \"Handle the user data\""
end
