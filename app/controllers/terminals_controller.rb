class TerminalsController < ApplicationController
  # GET /terminals
  # GET /terminals.xml
  def index
    @terminals = Terminal.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @terminals }
    end
  end

  # GET /terminals/1
  # GET /terminals/1.xml
  def show
    @terminal = Terminal.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @terminal }
    end
  end

  # GET /terminals/new
  # GET /terminals/new.xml
  def new
    @terminal = Terminal.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @terminal }
    end
  end

  # GET /terminals/1/edit
  def edit
    @terminal = Terminal.find(params[:id])
  end

  # POST /terminals
  # POST /terminals.xml
  def create
    @terminal = Terminal.new(params[:terminal])

    respond_to do |format|
      if @terminal.save
        flash[:notice] = 'Terminal was successfully created.'
        format.html { redirect_to(@terminal) }
        format.xml  { render :xml => @terminal, :status => :created, :location => @terminal }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @terminal.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /terminals/1
  # PUT /terminals/1.xml
  def update
    @terminal = Terminal.find(params[:id])

    respond_to do |format|
      if @terminal.update_attributes(params[:terminal])
        flash[:notice] = 'Terminal was successfully updated.'
        format.html { redirect_to(@terminal) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @terminal.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /terminals/1
  # DELETE /terminals/1.xml
  def destroy
    @terminal = Terminal.find(params[:id])
    @terminal.destroy

    respond_to do |format|
      format.html { redirect_to(terminals_url) }
      format.xml  { head :ok }
    end
  end
end
