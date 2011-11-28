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
    @student_year_class.cn = @school.cn + "-opp-" + params[:student_year_class][:puavoSchoolStartYear]
    @student_year_class.puavoSchool = @school.dn.to_s
    @student_year_class.student_class_ids = params[:student_class_id]
    @student_year_class.save!

    respond_to do |format|
      format.html { redirect_to( student_year_class_path(@school, @student_year_class) ) }
    end
  end
end
