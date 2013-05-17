require "./test/helper"

describe PuavoRest::LtspServersModel do

  before(:each) do
    path = "/tmp/puavo-rest-test.pstore"
    @model = PuavoRest::LtspServersModel.new(path)
    File.unlink(path) rescue Errno::ENOENT
  end

  it "can save server load data" do
    @model.set("test", :load_avg => 0.1)
    data = @model.get("test")
    assert_equal data[:domain], "test"
    assert_in_delta 0.1, data[:load_avg], 0.01
  end

  it "can figure out the most idle server" do
    @model.set("loaded", :load_avg => 1.1)
    @model.set("idle", :load_avg => 0.1)
    assert_equal "idle", @model.most_idle[:domain]
  end

  it "can figure out the most idle server" do
    @model.set("too-old", :load_avg => 0.0)
    Timecop.travel 60 * 5
    @model.set("littleload", :load_avg => 0.1)
    @model.set("lotload", :load_avg => 1.1)

    assert_equal "littleload", @model.most_idle[:domain]
  end

  # it "can filter servers by image" do
  #   @model.set("server1", :load_avg => 0.0, :ltsp_image => "foo")
  #   @model.set("server2", :load_avg => 0.0, :ltsp_image => "bar")

  #   assert_equal "server2", @model.most_idle("foo")[:domain]
  # end


end
