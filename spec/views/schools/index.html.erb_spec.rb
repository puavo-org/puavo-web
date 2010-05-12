require 'spec_helper'

describe "/schools/index.html.erb" do
  include SchoolsHelper

  before(:each) do
    assigns[:schools] = [
      stub_model(School,
        :name => "value for name",
        :name_abbreviation => "value for name_abbreviation",
        :locality => "value for locality",
        :address => "value for address"
      ),
      stub_model(School,
        :name => "value for name",
        :name_abbreviation => "value for name_abbreviation",
        :locality => "value for locality",
        :address => "value for address"
      )
    ]
  end

  it "renders a list of schools" do
    render
    response.should have_tag("tr>td", "value for name".to_s, 2)
    response.should have_tag("tr>td", "value for name_abbreviation".to_s, 2)
    response.should have_tag("tr>td", "value for locality".to_s, 2)
    response.should have_tag("tr>td", "value for address".to_s, 2)
  end
end
