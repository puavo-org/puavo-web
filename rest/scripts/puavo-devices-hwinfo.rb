#!/usr/bin/ruby1.9.1

require 'bundler/setup'
require_relative "../puavo-rest"
require "elasticsearch"

def hwinfo(domain, hostname)
  @es_client = Elasticsearch::Client.new(:url => CONFIG["elasticsearch"]["url"])

  timestamp = nil
  today = Date.today
  indices = (1..180).map do |i|
    (today - i).strftime("fluentd-puavo-hw-log-%Y.%m.%d")
  end

  indices.each do |indice|
    begin
      query = "msg: \"hwinfo\" AND meta.device_source.hostname: \"#{ hostname }\" AND meta.device_source.organisation_domain: \"#{ domain }\""
      res = @es_client.search({
                          :ignore_unavailable => true,
                          :index => Array(indice),
                          :body => {
                            :_source => true,
                            :sort =>  { "@timestamp" => { :order => "asc" }},
                            :query => {
                              :filtered => {
                                :query => {
                                  :query_string => {
                                    :analyze_wildcard => true,
                                    :query => query
                                  }
                                }
                              }
                            }
                          }
                        })
      if res["hits"]["total"] > 0
        return res["hits"]["hits"][0]["_source"]
      end

    rescue Elasticsearch::Transport::Transport::Errors::NotFound => err
      STDERR.puts err.to_s
      STDERR.puts
      STDERR.puts "Cannot find hwinfo for host"
    end

  end

  return ""
end

puts "Password for uid=admin,o=puavo user: "
password = STDIN.gets.strip

LdapModel.setup(
  :credentials => CONFIG["server"],
  :rest_root => "DUMMY"
)

file = File.open("/tmp/puavo-devices-hwinfo.json", "w")

PuavoRest::Organisation.all.each do |o|
  puts o.domain

  hwinfo_by_hostname = {}

  LdapModel.setup(
    :organisation => PuavoRest::Organisation.by_domain!(o.domain),
    :credentials => { :dn => "uid=admin,o=puavo", :password => password }
  )

  PuavoRest::Device.by_attr(:type, "fatclient", :multiple => true).each do |device|
    puts device.hostname + "." + o.domain
    hwinfo_by_hostname[device.hostname + "." + o.domain] = hwinfo(o.domain, device.hostname)
  end

  file.write(hwinfo_by_hostname.to_json)
end

file.close
