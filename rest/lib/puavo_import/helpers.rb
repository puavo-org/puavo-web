# -*- coding: utf-8 -*-

require 'optparse'

module PuavoImport
  module Helpers

    @@log_files = {}


    def log_to_file(file)
      return @@log_files[file] if @@log_files[file]

      filename = Time.now.strftime(file + "-%Y-%m-%d-%H-%M-%S")

      @@log_files[file] = {
        :filename => filename,
        :file => File.new(filename,  "w+")
      }
    end

    def cmd_options(args = {}, &block)
      options = {
        :encoding => 'ISO8859-1',
        :mode => "import"
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: puavo-import-schools [options] <CSV file>

#{ args[:message] }

"

        opts.on("--organisation-domain DOMAIN", "Domain of organisation") do |o|
          options[:organisation_domain] = o
        end

        opts.on("--character-encoding ENCODING", "Character encoding of the CSV file") do |encoding|
          options[:encoding] = encoding
        end

        opts.on("--initialize", "Initialize import to existing data by guessing external ids") do |m|
          options[:mode] = "set-external-id"
        end

        opts.on("--diff", "Show only differences without changes") do |m|
          options[:mode] = "diff"
        end

        opts.on("--dn DN", "User dn for LDAP connection") do |dn|
          options[:dn] = dn
        end

        opts.on("--password PASSWORD", "User password for LDAP connection") do |password|
          options[:password] = password
        end

        opts.on("--include-schools x,y,z", Array) do |include_schools|
          options[:include_schools] = include_schools
        end

        block.call(opts, options) unless block.nil?

        opts.on_tail("-h", "--help", "Show this message") do
          STDERR.puts opts
          Process.exit()
        end
      end

      parser.parse!

      unless args[:no_csv_file]
        if ARGV[0]
          options[:csv_file] = ARGV[0]
        else
          STDERR.puts parser
          exit 1
        end
      end

      return options
    end

    def encode_text(data, encoding)
      data.map do |data|
        next if data.nil?
        data.encode('utf-8', encoding)
      end
    end

    def sanitize_name(name)
      sanitized_name = name.downcase
      sanitized_name.gsub!(/[åäö ]/, "å" => "a", "ä" => "a", "ö" => "o", " " => "-")
      sanitized_name.gsub!(/[^a-z0-9-]/, "")

      return sanitized_name
    end

    def diff_objects(object_a, object_b, attributes)

      different_attributes = []

      attr_name_lenght = attributes.max{|a,b| a.length <=> b.length }.length + 2
      spacing = 50

      lines = []
      lines.push("%-#{ attr_name_lenght + spacing - 8 }s %s" % [object_a.class.to_s, object_b.class.to_s])

      attributes.each do |attr|
        a_value = object_a.send(attr)
        b_value = object_b.send(attr)

        if a_value != b_value
          different_attributes.push(attr)
          a_value = brown(a_value)
          b_value = red(b_value)
        else
          a_value = green(a_value)
          b_value = green(b_value)
        end

        values = ["#{ attr }:", a_value] + ["#{ attr }:", b_value]
        format = "%-#{ attr_name_lenght }s %-#{ spacing }s %-#{ attr_name_lenght }s %s"
        lines.push(format % values)
      end
      lines.each do |l|
        puts l
      end

      return different_attributes
    end

    def colorize(text, color_code)
      "\e[#{color_code}m#{text}\e[0m"
    end

    def red(text); colorize(text, 31); end

    def green(text); colorize(text, 32); end

    def brown(text); colorize(text, 33); end

    def ask(question, opts={})
      new_value = nil
      while true
        print "#{question} [#{ opts[:default] }]"
        print "(optional)" if opts[:optional]
        print "> "
        new_value = STDIN.gets.strip

        # Use default or previous value if user did not give anything
        new_value =  opts[:default] if new_value.to_s.empty?

        # Break if we have value
        break if not new_value.to_s.empty?

        # Allow empty value in optional
        break if opts[:optional]
      end
      new_value
    end

    def setup_connection(options)
      credentials = CONFIG["server"]

      if options[:dn] && options[:password]
        credentials = {
          :dn => options[:dn],
          :password => options[:password]
        }
      end

      LdapModel.setup(
        :credentials => credentials
      )

      LdapModel.setup(
        :organisation => PuavoRest::Organisation.by_domain!(options[:organisation_domain])
      )
    end

  end
end
