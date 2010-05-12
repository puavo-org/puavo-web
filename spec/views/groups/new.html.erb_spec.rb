require 'spec_helper'

describe "/groups/new.html.erb" do
  include GroupsHelper

  before(:each) do
    assigns[:group] = stub_model(Group,
      :new_record? => true,
      :name => "value for name",
      :owner => "value for owner",
      :type => "value for type"
    )
  end

  it "renders new group form" do
    render

    response.should have_tag("form[action=?][method=post]", groups_path) do
      with_tag("input#group_name[name=?]", "group[name]")
      with_tag("input#group_owner[name=?]", "group[owner]")
      with_tag("input#group_type[name=?]", "group[type]")
    end
  end
end
