module PuavoImport

  def self.cmd_options(args = {})
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

      opts.on("--import", "Write mode") do |i|
        options[:import] = i
      end

      opts.on_tail("-h", "--help", "Show this message") do
        STDERR.puts opts
        Process.exit()
      end
    end.parse!

    # FIXME: required arguments?

    return options
  end

  def self.csv_row_to_array(row, encoding)
    data = row.first.split(";")
    data.map do |data|
      data.encode('utf-8', encoding)
    end
  end

  def self.sanitize_name(name)
    sanitized_name = name.downcase
    sanitized_name.gsub!(/[åäö ]/, "å" => "a", "ä" => "a", "ö" => "o", " " => "-")
    sanitized_name.gsub!(/[ÅÄÖ]/, "Å" => "a", "Ä" => "a", "Ö" => "o")
    sanitized_name.gsub!(/[^a-z0-9-]/, "")

    return sanitized_name
  end
end
