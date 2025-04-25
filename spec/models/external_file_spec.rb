require 'spec_helper'


describe ExternalFile, :type => :model do
  it "can save " do
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = "filename"
    f.save!

    hash = Digest::SHA1.new.update(f.puavoData).to_s
    expect(ExternalFile.first.puavoDataHash).to eq(hash)
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
    expect(files.size).to eq(1)
    expect(files.first.cn).to eq("findme.txt")
  end

  it "can create by cn" do
    name = "newfile.txt"
    f = ExternalFile.find_or_create_by_cn(name)
    expect(f.cn).to eq(name)
    expect(f.puavoData).to eq(nil)
  end

  it "can find by cn" do
    name = "findme.txt"
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = name
    f.save!

    f2 = ExternalFile.find_or_create_by_cn(name)
    expect(f2.cn).to eq(name)
    expect(f2.puavoData).to eq("lol")
  end

  it "can serialize to nice json" do
    f = ExternalFile.new
    f.puavoData = "lol"
    f.cn = "filename.txt"
    f.save!

    json = f.as_json

    # id sequence is not reseted between test runs. Assert everthing else
    expect(json.keys).to eq(["id", "name", "data_hash"])
    expect(json["name"]).to eq("filename.txt")
    expect(json["data_hash"]).to eq("403926033d001b5279df37cbbe5287b7c7c267fa")
    expect(json["id"].class).to eq(Fixnum)
  end


  describe "binary files" do

    it "can save non utf-8 files" do
      f = ExternalFile.new
      f.cn = "image"
      image_data = File.open(img_path, "rb").read
      f.puavoData = image_data
      f.save!

      saved = ExternalFile.find_or_create_by_cn("image")
      expect(saved.puavoDataHash).not_to eq(nil)
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
      expect(saved.puavoDataHash).not_to eq(nil)
    end
  end

end
