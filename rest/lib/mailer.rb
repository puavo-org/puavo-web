require "pony"

module PuavoRest

  class Mailer

    def initialize
      if CONFIG["password_management"]
        @options = { :via => :smtp }
        @options.merge!(CONFIG["password_management"]["smtp"])
        @options.recursive_symbolize_keys!
      end
    end

    def send(args)
      email_options = args.merge(@options)
      Pony.mail(email_options)
    end

    def options
      @options
    end

  end
end
