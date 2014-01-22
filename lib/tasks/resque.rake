
require "resque/tasks"

# load full rails env in the worker
task "resque:setup" => :environment
