require 'spec_helper'

describe "/groups/show.html.erb" do
  include GroupsHelper
  before(:each) do
    assigns[:group] = @group = stub_model(Group,
      :name => "value for name",
      :owner => "value for owner",
      :type => "value for type"
    )
  end

  it "renders attributes in <p>" do
    render
    response.should have_text(/value\ for\ name/)
    response.should have_text(/value\ for\ owner/)
    response.should have_text(/value\ for\ type/)
  end
end
