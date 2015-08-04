module PuavoImport

  def self.cmd_options
    options = { :encoding=> 'ISO8859-1' }

    OptionParser.new do |opts|
      opts.banner = "Usage: puavo-import-schools [options]

Import schools to Puavo

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

    return options
  end
end
