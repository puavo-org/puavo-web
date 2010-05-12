require 'spec_helper'

describe "/schools/show.html.erb" do
  include SchoolsHelper
  before(:each) do
    assigns[:school] = @school = stub_model(School,
      :name => "value for name",
      :name_abbreviation => "value for name_abbreviation",
      :locality => "value for locality",
      :address => "value for address"
    )
  end

  it "renders attributes in <p>" do
    render
    response.should have_text(/value\ for\ name/)
    response.should have_text(/value\ for\ name_abbreviation/)
    response.should have_text(/value\ for\ locality/)
    response.should have_text(/value\ for\ address/)
  end
end
