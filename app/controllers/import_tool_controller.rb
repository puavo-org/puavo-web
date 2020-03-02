class ImportToolController < ApplicationController
  def index
    return unless is_owner?

    school = School.find(params["school_id"])
    @import_tool_options = {
      "containerId" => "import-tool", # the html element id
      "useGroupsOnly" => new_group_management?(@school),
      "school" => {
        "dn" => school.dn.to_s,
        "id" => school.puavo_id
      }
    }
  end
end
