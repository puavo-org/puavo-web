require 'spec_helper'

describe "/users/import/preview" do
  before(:each) do
    render 'users/import/preview'
  end

  #Delete this example and add some real ones or delete this file
  it "should tell you where to find the file" do
    response.should have_tag('p', %r[Find me in app/views/users/import/preview])
  end
end
