require "date"
require "fileutils"

module PuavoRest
class Primus < LdapSinatra

  post "/v3/primus/:filename" do
    primus_config = CONFIG["primus"]

    if primus_config.nil?
      raise InternalError, :user => "Primus resource is not configured"
    end

    proposed = basic_auth()
    if proposed.nil? || proposed[:username].to_s.empty? || proposed[:password].to_s.empty?
      raise Unauthorized, :user => "No credentials provided"
    end

    if proposed[:password] != primus_config["users"][proposed[:username]]
      raise Unauthorized, :user => "Bad credentials"
    end

    is_multipart = request.content_type.downcase.strip.start_with?("multipart/form-data")
    incoming_file = nil

    if request.content_type.downcase.strip == "text/csv"
      incoming_file = request.body
    elsif is_multipart && params["file"].kind_of?(Hash)
      incoming_file = params["file"][:tempfile]
    else
      raise BadInput, :user => "cannot find file"
    end

    dir = File.join(
      primus_config["directory"],
      proposed[:username],
      DateTime.now.strftime("%Y-%m-%d")
    )

    FileUtils.mkdir_p(dir)

    meta = {
      "filename" => params["filename"]
    }

    File.open(File.join(dir, params["filename"]), "w") do |f|
      meta["bytes_written"] = IO.copy_stream(incoming_file, f)
    end

    flog.info "wrote primus file", meta

    json meta
  end

end
end
