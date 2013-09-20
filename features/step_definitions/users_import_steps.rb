Given(/^I send to the following user mass import data$/) do |raw_data|
  step "I am on the new user import page"
  step "I fill in textarea \"raw_users\" with \"#{raw_data}\""
  step "I press \"Handle the user data\""
end
