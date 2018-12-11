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

    @external_files.sort!{|a, b| a["meta"]["name"].downcase <=> b["meta"]["name"].downcase }

    respond_to do |format|
      format.html # index.html.erb
      format.json { render :json => file_models }
    end
  end


  # GET /external_files/:name
  def get_file
    cn = params[:name]
    if ef = ExternalFile.find_by_cn(cn)
      render(
        :content_type => 'application/octet-stream',
        :plain => ef.puavoData
      )
    else
      render(
        :status => 404,
        :plain => t('external_files.file_not_found')
      )
    end

  end

  # POST /external_files
  def upload
    begin
      if params["file"]
          params["file"].each do |k, file|
            f = ExternalFile.find_or_create_by_cn(k)
            data = File.open(file.path, "rb").read.to_blob
            f.puavoData = data
            f.save!
          end
      end

      flash[:notice] = t('external_files.changes_saved')
      redirect_to :back
    rescue StandardError => e
      puts e
      flash[:alert] = t('external_files.changes_failed')
      redirect_to :back
    end
  end

  # DELETE /external_files/:name
  def destroy
    cn = params[:name]
    @external_file = ExternalFile.find_by_cn(cn)
    if not @external_file
      return render(:status => 404, :plain => t('external_files.file_not_found'))
    end

    @external_file.destroy
    respond_to do |format|
      format.html { redirect_to external_files_url }
      format.json { head :no_content }
    end
  end
end
