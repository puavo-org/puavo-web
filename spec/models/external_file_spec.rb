require 'spec_helper'


describe ExternalFile do
  it "can save " do
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = "filename"
    f.save!

    hash = Digest::SHA1.new.update(f.puavoData).to_s
    ExternalFile.first.puavoDataHash.should == hash
  end

  it "can find configured files" do
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = "findme.txt"
    f.save!

    f = ExternalFile.new
    f.puavoData = "haha"
    f.cn = "butnotme.txt"
    f.save!

    files = ExternalFile.find_configured([{ "name" => "findme.txt" }])
    files.size.should == 1
    files.first.cn.should == "findme.txt"
  end

  it "can create by cn" do
    name = "newfile.txt"
    f = ExternalFile.find_or_create_by_cn(name)
    f.cn.should == name
    f.puavoData.should == nil
  end

  it "can find by cn" do
    name = "findme.txt"
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = name
    f.save!

    f2 = ExternalFile.find_or_create_by_cn(name)
    f2.cn.should == name
    f2.puavoData.should == "lol"
  end

  it "can serialize to nice json" do
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = "filename.txt"
    f.save!

    f.as_json.should equal({
      "id" => 31,
      "name" => "filename.txt",
      "hash" => "403926033d001b5279df37cbbe5287b7c7c267fa"
    })
  end


  describe "binary files" do
    img_path = File.join(File.dirname(__FILE__), "img.jpg")

    it "can save non utf-8 files" do
      f = ExternalFile.new
      f.cn = "image"
      image_data = File.open(img_path, "rb").read
      f.puavoData = image_data
      f.save!

      saved = ExternalFile.find_or_create_by_cn("image")
      saved.puavoDataHash.should_not be_nil
    end

    it "can change files" do
      f = ExternalFile.new
      f.cn = "image"
      image_data = File.open(img_path, "rb").read
      f.puavoData = image_data
      f.save!

      saved = ExternalFile.find_or_create_by_cn("image")
      saved.puavoData = "new data"
      saved.save!
      saved.puavoDataHash.should_not be_nil
    end
  end

end
