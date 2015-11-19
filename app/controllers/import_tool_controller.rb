class ImportToolController < ApplicationController
  def index
    school = School.find(params["school_id"])
    @import_tool_options = {
      "containerId" => "import-tool", # the html element id
      "useGroupsOnly" => false,
      "school" => {
        "dn" => school.dn.to_s,
        "id" => school.puavo_id
      }
    }
  end
end
