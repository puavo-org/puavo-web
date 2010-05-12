require 'spec_helper'

describe SchoolsController do
  describe "routing" do
    it "recognizes and generates #index" do
      { :get => "/schools" }.should route_to(:controller => "schools", :action => "index")
    end

    it "recognizes and generates #new" do
      { :get => "/schools/new" }.should route_to(:controller => "schools", :action => "new")
    end

    it "recognizes and generates #show" do
      { :get => "/schools/1" }.should route_to(:controller => "schools", :action => "show", :id => "1")
    end

    it "recognizes and generates #edit" do
      { :get => "/schools/1/edit" }.should route_to(:controller => "schools", :action => "edit", :id => "1")
    end

    it "recognizes and generates #create" do
      { :post => "/schools" }.should route_to(:controller => "schools", :action => "create") 
    end

    it "recognizes and generates #update" do
      { :put => "/schools/1" }.should route_to(:controller => "schools", :action => "update", :id => "1") 
    end

    it "recognizes and generates #destroy" do
      { :delete => "/schools/1" }.should route_to(:controller => "schools", :action => "destroy", :id => "1") 
    end
  end
end
