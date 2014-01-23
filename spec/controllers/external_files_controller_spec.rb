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

  describe "POST file" do
    it "can upload file to ldap" do
      file = fixture_file_upload(img_path, 'image/jpeg', :binary)

      @request.env['HTTP_REFERER'] = external_files_path
      post(:upload, {
        :file => {
          "img.jpg" => file
        }
      }, valid_session)

      Puavo::Test.setup_test_connection
      ExternalFile.find_by_cn("img.jpg").should_not be_nil
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
      get :get_file, { :name => "another.txt" }, valid_session
      expect(response.status).to eq(404)
    end
  end

  describe "DELETE file" do

    it "deletes file" do
      f = ExternalFile.new
      f.puavoData = "data"
      f.cn = "new.txt"
      f.save!

      delete :destroy, { :name => "new.txt" }, valid_session

      # Doing accessing controller removes the ldap connection for some reason.
      # Restore it...
      Puavo::Test.setup_test_connection
      ExternalFile.find_by_cn("new.txt").should == nil
    end

    it "responds 404 on nonexistent file" do
      delete :destroy, { :name => "nofile.txt" }, valid_session
      expect(response.status).to eq(404)
    end

  end

end
