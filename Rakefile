require 'rake'
require 'rake/testtask'
require 'rdoc/task'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    root_files = FileList["README.rdoc", "COPYING", "init.rb"]
    s.name = "puavo_authentication"
    s.summary = "Authentication solution for Puavo applications"
    s.email = "puavo@opinsys.fi"
    s.homepage = "http://github.com/opinsys/puavo_authentication"
    s.description = "Authentication solution for Puavo applications"
    s.authors = "Jouni Korhonen"
    s.files =  root_files + FileList["{app,rails,lib}/**/*"]
    s.extra_rdoc_files = root_files
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler, or one of its dependencies, is not available. Install it with: gem install jeweler"
end


require "rspec/core/rake_task"
RSpec::Core::RakeTask.new
