require_relative "./helper"

describe PuavoRest::LtspServersModel do

  before(:each) do
    path = "/tmp/puavo-rest-test.pstore"
    @model = PuavoRest::LtspServersModel.new(path)
    File.unlink(path) rescue Errno::ENOENT
  end

  it "can save server load data" do
    @model.set_server("test", :load_avg => 0.1)
    data = @model.get("test")
    assert_equal data[:hostname], "test"
    assert_in_delta 0.1, data[:load_avg], 0.01
  end

  it "can figure out the most idle server" do
    @model.set_server("loaded", :load_avg => 1.1)
    @model.set_server("idle", :load_avg => 0.1)
    assert_equal "idle", @model.most_idle.first[:hostname]
  end

  it "can figure out the most idle server" do
    @model.set_server("too-old", :load_avg => 0.0)
    Timecop.travel 60 * 5
    @model.set_server("littleload", :load_avg => 0.1)
    @model.set_server("lotload", :load_avg => 1.1)

    assert_equal "littleload", @model.most_idle.first[:hostname]
  end

  it "can filter servers by image" do
    @model.set_server("server1", :load_avg => 0.0, :ltsp_image => "foo")
    @model.set_server("server2", :load_avg => 0.0, :ltsp_image => "bar")

    assert_equal "server1", @model.most_idle("foo").first[:hostname]
  end


end
