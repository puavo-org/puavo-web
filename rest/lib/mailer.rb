require "pony"

module PuavoRest

  class Mailer

    def initialize
      @options = { :via => :smtp }
      @options.merge!(CONFIG["password_management"]["smtp"])
      @options.recursive_symbolize_keys!
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
