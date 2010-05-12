require 'spec_helper'

describe "/groups/index.html.erb" do
  include GroupsHelper

  before(:each) do
    assigns[:groups] = [
      stub_model(Group,
        :name => "value for name",
        :owner => "value for owner",
        :type => "value for type"
      ),
      stub_model(Group,
        :name => "value for name",
        :owner => "value for owner",
        :type => "value for type"
      )
    ]
  end

  it "renders a list of groups" do
    render
    response.should have_tag("tr>td", "value for name".to_s, 2)
    response.should have_tag("tr>td", "value for owner".to_s, 2)
    response.should have_tag("tr>td", "value for type".to_s, 2)
  end
end
