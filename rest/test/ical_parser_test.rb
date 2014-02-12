require_relative "./helper"

module ICALParser_test
DIR = File.expand_path File.dirname(__FILE__)

describe ICALParser do

  before(:each) do
    t = Time.local(2014, 2, 12, 14, 5, 0)
    Timecop.travel(t)
  end

  after(:each) do
    Timecop.return
  end

  it "can find current events" do
    cal = ICALParser.parse File.open(DIR + "/fixtures/ical.ics", "r")

    assert_equal([
      {"message"=>"long event"},
      {"message"=>"event of today"}
    ], cal.current_events)
  end

end
end
