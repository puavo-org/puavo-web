require_relative "./helper"

module ICALParser_test

describe ICALParser do

  before(:each) do
    Timecop.travel(Fixtures::ICS_TIME)
  end

  after(:each) do
    Timecop.return
  end

  it "can find current events" do
    cal = ICALParser.parse File.open(Fixtures::ICS_FILE, "r")

    assert_equal([
      {"message"=>"long event"},
      {"message"=>"event of today"}
    ], cal.current_events)
  end

end

end
