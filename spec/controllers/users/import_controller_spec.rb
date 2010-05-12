require 'spec_helper'

describe Users::ImportController do

  #Delete these examples and add some real ones
  it "should use Users::ImportController" do
    controller.should be_an_instance_of(Users::ImportController)
  end


  describe "GET 'new'" do
    it "should be successful" do
      get 'new'
      response.should be_success
    end
  end

  describe "GET 'validate'" do
    it "should be successful" do
      get 'validate'
      response.should be_success
    end
  end

  describe "GET 'group'" do
    it "should be successful" do
      get 'group'
      response.should be_success
    end
  end

  describe "GET 'preview'" do
    it "should be successful" do
      get 'preview'
      response.should be_success
    end
  end

  describe "GET 'create'" do
    it "should be successful" do
      get 'create'
      response.should be_success
    end
  end

  describe "GET 'show'" do
    it "should be successful" do
      get 'show'
      response.should be_success
    end
  end
end
