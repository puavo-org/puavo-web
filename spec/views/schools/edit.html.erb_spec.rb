require 'spec_helper'

describe "/schools/edit.html.erb" do
  include SchoolsHelper

  before(:each) do
    assigns[:school] = @school = stub_model(School,
      :new_record? => false,
      :name => "value for name",
      :name_abbreviation => "value for name_abbreviation",
      :locality => "value for locality",
      :address => "value for address"
    )
  end

  it "renders the edit school form" do
    render

    response.should have_tag("form[action=#{school_path(@school)}][method=post]") do
      with_tag('input#school_name[name=?]', "school[name]")
      with_tag('input#school_name_abbreviation[name=?]', "school[name_abbreviation]")
      with_tag('input#school_locality[name=?]', "school[locality]")
      with_tag('input#school_address[name=?]', "school[address]")
    end
  end
end
