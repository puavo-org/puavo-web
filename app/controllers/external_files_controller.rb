class ExternalFilesController < ApplicationController
  # GET /external_files
  # GET /external_files.json
  def index

    file_models = ExternalFile.find_configured
 
    @external_files =  Puavo::EXTERNAL_FILES.map do |meta|
      {
        "meta" => meta,
        "model" => file_models.select do |m|
          meta["name"] == m.cn
        end.first
      }
    end

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @external_files }
    end
  end

  # POST
  def create
    return if not params["file"]
    params["file"].each do |k, file|
      f = ExternalFile.find_or_create_by_cn(k)

      data = File.open(file.path, "rb").read.to_blob
      f.puavoData = data
      f.save!
    end
    redirect_to :back
  end

  # DELETE /external_files/1
  # DELETE /external_files/1.json
  def destroy
    @external_file = ExternalFile.find(params[:id])
    @external_file.destroy

    respond_to do |format|
      format.html { redirect_to external_files_url }
      format.json { head :no_content }
    end
  end
end
