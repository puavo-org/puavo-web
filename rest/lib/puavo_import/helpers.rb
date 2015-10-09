# -*- coding: utf-8 -*-
module PuavoImport
  module Helpers

    def cmd_options(args = {}, &block)
      options = { :encoding=> 'ISO8859-1' }

      OptionParser.new do |opts|
        opts.banner = "Usage: puavo-import-schools [options]

#{ args[:message] }

"

        opts.on("--organisation-domain DOMAIN", "Domain of organisation") do |o|
          options[:organisation_domain] = o
        end

        opts.on("--csv-file FILE", "csv file with schools") do |o|
          options[:csv_file] = o
        end

        opts.on("--character-encoding ENCODING", "Character encoding of CSV file") do |encoding|
          options[:encoding] = encoding
        end

        opts.on("--mode MODE", "Write mode") do |m|
          options[:mode] = m
        end

        block.call(opts, options) unless block.nil?

        opts.on_tail("-h", "--help", "Show this message") do
          STDERR.puts opts
          Process.exit()
        end
      end.parse!

      # FIXME: required arguments?

      return options
    end

    def csv_row_to_array(row, encoding)
      data = row.first.split(";")
      data.map do |data|
        data.encode('utf-8', encoding)
      end
    end

    def sanitize_name(name)
      sanitized_name = name.downcase
      sanitized_name.gsub!(/[åäö ]/, "å" => "a", "ä" => "a", "ö" => "o", " " => "-")
      sanitized_name.gsub!(/[ÅÄÖ]/, "Å" => "a", "Ä" => "a", "Ö" => "o")
      sanitized_name.gsub!(/[^a-z0-9-]/, "")

      return sanitized_name
    end

    def diff_objects(object_a, object_b, attributes)

      attr_name_lenght = attributes.max{|a,b| a.length <=> b.length }.length + 2
      spacing = 50

      lines = []
      lines.push("%-#{ attr_name_lenght + spacing - 8 }s %s" % [object_a.class.to_s, object_b.class.to_s])

      attributes.each do |attr|
        a_value = object_a.send(attr)
        b_value = object_b.send(attr)

        if a_value != b_value
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
    end

    private
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

  end
end
