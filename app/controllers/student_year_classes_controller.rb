class StudentYearClassesController < ApplicationController

  # GET /:school_id/student_year_classes/
  def index
    @student_year_classes = StudentYearClass.find( :all,
                                                   :attribute => "puavoSchool",
                                                   :value => @school.dn.to_s )
    

    respond_to do |format|
      format.html
    end
  end

  # GET /:school_id/student_year_classes/
  def show
    @student_year_class = StudentYearClass.find(params[:id])
    @student_classes = @student_year_class.student_classes.map do |student_class|
      student_class.displayName
    end.join(", ")
    
    respond_to do |format|
      format.html
    end
  end

  # GET /:school_id/student_year_classes/new
  def new
    @student_year_class = StudentYearClass.new

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/student_year_classes/
  def create
    @student_year_class = StudentYearClass.new(params[:student_year_class])
    @student_year_class.puavoSchool = @school.dn.to_s
    @student_year_class.save!

    respond_to do |format|
      format.html { redirect_to( student_year_class_path(@school, @student_year_class) ) }
    end
  end

  # GET /:school_id/student_year_classes/edit
  def edit
    @student_year_class = StudentYearClass.find(params[:id])

    respond_to do |format|
      format.html
    end
  end

  # PUT /:school_id/student_year_classes/:id
  def update
    @student_year_class = StudentYearClass.find(params[:id])

    respond_to do |format|
      if @student_year_class.update_attributes(params[:student_year_class])
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.student_year_class'))
        format.html { redirect_to( student_year_class_path(@school, @student_year_class) ) }
      else
        flash[:alert] = t('flash.student_year_class.save_failed')
        format.html { render :action => "edit" }
      end

    end
  end
end
