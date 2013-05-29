# registering_devices feature needs Capybara servero for testing


module Puavo
  mattr_accessor :start_test_server
end

module Capybara
  module RackTest
    class Driver
      def needs_server?
        Puavo.start_test_server ? true : super
      end
    end
  end

  class Session

    def remove_server
      @server = nil
    end
  end
end
