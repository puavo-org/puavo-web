class ExternalFilesController < ApplicationController
  # GET /external_files
  # GET /external_files.json
  def index
    @external_files = ExternalFile.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @external_files }
    end
  end

  # GET /external_files/1
  # GET /external_files/1.json
  def show
    @external_file = ExternalFile.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @external_file }
    end
  end

  # GET /external_files/new
  # GET /external_files/new.json
  def new
    @external_file = ExternalFile.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @external_file }
    end
  end

  # GET /external_files/1/edit
  def edit
    @external_file = ExternalFile.find(params[:id])
  end

  # POST /external_files
  # POST /external_files.json
  def create
    @external_file = ExternalFile.new(params[:external_file])

    respond_to do |format|
      if @external_file.save
        format.html { redirect_to @external_file, notice: 'External file was successfully created.' }
        format.json { render json: @external_file, status: :created, location: @external_file }
      else
        format.html { render action: "new" }
        format.json { render json: @external_file.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /external_files/1
  # PUT /external_files/1.json
  def update
    @external_file = ExternalFile.find(params[:id])

    respond_to do |format|
      if @external_file.update_attributes(params[:external_file])
        format.html { redirect_to @external_file, notice: 'External file was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @external_file.errors, status: :unprocessable_entity }
      end
    end
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
