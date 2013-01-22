class ConfigurationFilesController < ApplicationController


  # GET /configuration_files
  def index
    @select_options = []
    Puavo::CONFIGURATION_FILES.each do |key, value|
      @select_options.push( [value["filename"], key ] )
    end

    @files = ConfigurationFile.all

    @file = ConfigurationFile.new

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # GET /configuration_files/1
  def show
    @file = ConfigurationFile.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
    end
  end

  # GET /configuration_files/new
  def new
    @file = ConfigurationFile.new

    respond_to do |format|
      format.html # new.html.erb
    end
  end

  # GET /configuration_files/1/edit
  def edit
    @file = ConfigurationFile.find(params[:id])
  end

  # POST /configuration_files
  def create
    @file = ConfigurationFile.new(params[:configuration_file])
    @file.puavoFileName = Puavo::CONFIGURATION_FILES[@file.puavoFileId]["filename"]

    respond_to do |format|
      if @file.save
        format.html { redirect_to( configuration_files_url,
                                   :notice => t('flash.added',
                                                :item => t('activeldap.models.configuration_file') ) ) }
      else
        format.html { render :action => "new" }
      end
    end
  end

  # PUT /configuration_files/1
  def update
    @file = ConfigurationFile.find(params[:id])

    respond_to do |format|
      if @file.update_attributes(params[:configuration_file])
        format.html { redirect_to( @file,
                                   :notice => t('flash.updated',
                                                :item => t('activeldap.models.configuration_file' ) ) ) }
      else
        format.html { render :action => "edit" }
      end
    end
  end

  # DELETE /configuration_files/1
  def destroy
    @file = ConfigurationFile.find(params[:id])
    @file.destroy

    respond_to do |format|
      format.html { redirect_to(configuration_files_url) }
    end
  end
end
