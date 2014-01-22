Given(/^I send to the following user mass import data$/) do |raw_data|
  step "I am on the new user import page"
  step "I fill in textarea \"raw_users\" with \"#{raw_data}\""
  step "I press \"Handle the user data\""
end



# Monkeypatch Resque to work synchronously to ease usage in Cucumber tests
module Resque
  def self.enqueue(klass, *args)

    # serialize args to json to "simulate" redis usage
    args = JSON.parse(args.to_json)

    klass.perform(*args)
  end
end
