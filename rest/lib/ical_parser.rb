
require "icalendar"

class ICALParser

  def self.parse(data)
    new Icalendar.parse(data)
  end

  def initialize(cals)
    @cals = cals
  end


  def current_events
    events = []

    @cals.each do |cal|
      cal.events.each do |event|
        range = (event.dtstart.to_time.to_i..event.dtend.to_time.to_i)
        if range.cover?(Time.now.to_i)
          events.push({
            "message" => event.summary
          })
        end
      end
    end

    return events

  end

end

