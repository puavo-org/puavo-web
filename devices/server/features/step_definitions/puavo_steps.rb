Given /^I am on the devices page with "([^\"]*)" school$/ do |school_name|
  @school = School.find(:attribute => "displayName", :value => school_name)
  visit devices_path(@school)
end
