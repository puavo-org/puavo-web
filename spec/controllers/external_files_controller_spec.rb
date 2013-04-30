require 'spec_helper'

describe ExternalFilesController do

  before(:each) do
    controller.request.host = 'www.example.com'

    # XXX: Prints warnings on every test run
    Puavo::EXTERNAL_FILES = [
      {
        "name"=>"file.txt",
        "description" => "Just some test file"
      },
      {
        "name"=>"another.txt",
        "description" => "Another file for testing"
      }
    ]

    f = ExternalFile.new
    f.puavoData = "data"
    f.cn = "file.txt"
    f.save!
  end

  let(:valid_session) do
    {
      :uid => "cucumber",
      :password_plaintext => "cucumber"
    }
  end

  describe "GET index" do

    it "lists files" do
      get :index, { :format => :json }, valid_session
      expect(response.status).to eq(200)
      json = JSON.parse(response.body)

      json.size.should == 1
      json[0]["name"].should == "file.txt"
    end

  end

  describe "GET file" do
    it "can fetch saved file" do
      get :get_file, { :name => "file.txt" }, valid_session
      expect(response.status).to eq(200)
      response.body.should == "data"
    end

    it "responds 404 on non defined files" do
      get :get_file, { :name => "nofile.txt" }, valid_session
      expect(response.status).to eq(404)
    end

    it "responds 404 on nonexistent files" do
      res = get :get_file, { :name => "another.txt" }, valid_session
      expect(response.status).to eq(404)
    end

  end


end
