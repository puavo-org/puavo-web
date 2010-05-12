require 'spec_helper'

describe Group do
  before(:each) do
    @valid_attributes = {
      :name => "value for name",
      :owner => "value for owner",
      :type => "value for type"
    }
  end

  it "should create a new instance given valid attributes" do
    Group.create!(@valid_attributes)
  end
end
