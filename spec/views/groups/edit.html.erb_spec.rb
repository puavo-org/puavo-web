require 'spec_helper'

describe "/groups/edit.html.erb" do
  include GroupsHelper

  before(:each) do
    assigns[:group] = @group = stub_model(Group,
      :new_record? => false,
      :name => "value for name",
      :owner => "value for owner",
      :type => "value for type"
    )
  end

  it "renders the edit group form" do
    render

    response.should have_tag("form[action=#{group_path(@group)}][method=post]") do
      with_tag('input#group_name[name=?]', "group[name]")
      with_tag('input#group_owner[name=?]', "group[owner]")
      with_tag('input#group_type[name=?]', "group[type]")
    end
  end
end
