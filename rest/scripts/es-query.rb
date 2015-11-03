

require "elasticsearch"
require "optparse"
require "json"
require "debugger"

@options = {
  :days => 30,
  :ignore_unavailable => false,
  :all => false
}

script_name = File.basename(__FILE__)

parser = OptionParser.new do |opts|
  opts.banner = "Find first hit for a Lucene query from Elasticsearch

  Usage: #{script_name} <options> URL TAG QUERY

  Where

    - URL is the Elasticsearch URL. Use @ to add credentials if needed
    - TAG is a fluentd tag
    - QUERY is a Lucene query

  Example: Find last session for a username

    #{script_name} http://username:password@elastisearch.server.example puavo-rest 'msg: \"created session\" AND created\\ session.session.organisation: \"testorg.opinsys.fi\" AND created\\ session.session.user.username: \"testusername\"'

  "

  opts.on("-r", "--range DAYS", "How many days to search from history. Default #{ @options[:days] }") do |days|
    @options[:days] = days.to_i
  end

  opts.on("--ignore-unavailable", "Ignore unavailable indices") do
    @options[:ignore_unavailable] = true
  end

  opts.on("-a", "--all", "Return all hits in the given range") do
    @options[:all] = true
  end

  opts.on("-v", "--verbose", "Be verbose") do
    @options[:verbose] = true
  end

end

parser.parse!

if ARGV.size != 3
  STDERR.puts parser
  Process.exit 1
end

@options[:es_url] = ARGV[0]
@options[:tag] = ARGV[1]
@options[:query] = ARGV[2]

@es_client = Elasticsearch::Client.new :url => @options[:es_url]

def verbose(*a)
  if @options[:verbose]
    STDERR.puts(*a)
  end
end

def do_query(indices, query)
  indices = Array(indices)
  verbose "Using indices #{ indices.inspect }"
  verbose "Issuing a query: #{ query }"
  begin
    @es_client.search({
      :ignore_unavailable => @options[:ignore_unavailable],
      :index => indices,
      :body => {
        :_source => true,
        :sort =>  { "@timestamp" => { :order => "asc" }},
        :query => {
          :filtered => {
          :query => {
            :query_string => {
              :analyze_wildcard => true,
              # :query => 'msg: "created session" AND created\ session.session.organisation: "vihti.opinsys.fi" AND created\ session.session.user.username: "eino.ala-turkia"'
              :query => query
              }
            }
          }
        }
      }
    })
  rescue Elasticsearch::Transport::Transport::Errors::NotFound => err
    STDERR.puts err.to_s
    STDERR.puts
    STDERR.puts "Cannot find indices with tag: #{ @options[:tag] }"
    STDERR.puts "You may wanna try --ignore-unavailable if you have missing indices in the range"
    exit 3
  end

end


def err_exit
  STDERR.puts "Nothing found. Try longer --range ?"
  Process.exit 1
end

today = Date.today
indices = (1..@options[:days]).map do |i|
  (today - i).strftime("fluentd-#{ @options[:tag] }-%Y.%m.%d")
end


if @options[:all]
  res = do_query(indices, @options[:query])
  err_exit() if res["hits"]["total"] == 0
  STDOUT.puts res["hits"]["hits"].map{ |r| r["_source"]}.to_json
else
  indices.each do |index|
    res = do_query(index, @options[:query])
    if res["hits"]["total"] > 0
      STDOUT.puts res["hits"]["hits"][0]["_source"].to_json
      Process.exit 0
    end
  end
  err_exit()
end

