class AutomountsController < ApplicationController

  before_filter :find_server

  # GET /automounts
  # GET /automounts.xml
  def index
    @automounts = Automount.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @automounts }
    end
  end

  # GET /automounts/1
  # GET /automounts/1.xml
  def show
    @automount = Automount.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @automount }
    end
  end

  # GET /automounts/new
  # GET /automounts/new.xml
  def new
    @automount = Automount.new
    # @automount = Automount.new(:puavoServer => @server.dn)
    # @automount = @server.automounts.build

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @automount }
    end
  end

  # GET /automounts/1/edit
  def edit
    @automount = Automount.find(params[:id])
  end

  # POST /automounts
  # POST /automounts.xml
  def create
    @automount = Automount.new(params[:automount])
    @automount.puavoServer = @server.dn

    respond_to do |format|
      if @automount.save
        flash[:notice] = 'Automount was successfully created.'
        format.html { redirect_to([@server, @automount]) }
        format.xml  { render :xml => @automount, :status => :created, :location => @automount }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @automount.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /automounts/1
  # PUT /automounts/1.xml
  def update
    @automount = Automount.find(params[:id])

    respond_to do |format|
      if @automount.update_attributes(params[:automount])
        flash[:notice] = 'Automount was successfully updated.'
        format.html { redirect_to([@server, @automount]) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @automount.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /automounts/1
  # DELETE /automounts/1.xml
  def destroy
    @automount = Automount.find(params[:id])
    @automount.destroy

    respond_to do |format|
      format.html { redirect_to(server_automounts_url(@server)) }
      format.xml  { head :ok }
    end
  end

  private

  def find_server
    @server = Server.find(params[:server_id])
  end
end
