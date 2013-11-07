require_relative "./helper"
require_relative "../lib/fluent"


describe FluentWrap do

  [:info, :warn, :error].each do |level|
    it "flog##{ level }(...) sets log level" do
      logger = MockFluent.new

      flog = FluentWrap.new "testtag", {:meta_attr => true}, logger
      flog.send(level, "testmsg")


      assert logger.data, "has data"
      entry = logger.data.first
      assert_equal "testtag", entry.first, "has tag"

      assert_equal "testmsg", entry[1][:msg], "has msg"

      assert entry[1][:meta], "has meta"
      assert_equal level.to_s, entry[1][:meta][:level], "has level"
    end
  end

  it "cleans passwords" do
      logger = MockFluent.new
      flog = FluentWrap.new "testtag", {:password_in_base => "secret1"}, logger
      flog.info("testmsg", :password_in_arg => "secret2")

      assert logger.data, "has data"
      data = logger.data.first[1]
      assert_equal "*******", data[:password_in_arg]
      assert_equal "*******", data[:meta][:password_in_base]
  end

  it "cleans passwords from nested ActiveSupport::HashWithIndifferentAccess hashes" do
    logger = MockFluent.new
    flog = FluentWrap.new("testtag", {}, logger)

    flog.info("testmsg", ActiveSupport::HashWithIndifferentAccess.new(:params => {
      :user => {
        "new_password" => "secret1"
      }
    }))

    assert logger.data, "has data"
    data = logger.data.first[1]
    assert_equal "*******", data[:params][:user][:new_password]
  end


  it "can merge new meta variables" do
      logger = MockFluent.new
      flog = FluentWrap.new "testtag", {:meta_attr1 => true}, logger
      flog.info("testmsg1")

      assert logger.data, "has data"
      data = logger.data[0][1]
      assert_equal true, data[:meta][:meta_attr1]

      flog2 = flog.merge :meta_attr2 => true
      flog2.info("testmsg2")
      data = logger.data[1][1]
      assert_equal true, data[:meta][:meta_attr1]
      assert_equal true, data[:meta][:meta_attr2]
  end

end
