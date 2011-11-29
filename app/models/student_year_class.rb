class StudentYearClass < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Classes,ou=Groups",
                :classes => ['top', 'posixGroup', 'puavoYearClass','sambaGroupMapping'] )

  belongs_to( :school, :class_name => 'School',
              :foreign_key => 'puavoSchool',
              :primary_key => 'dn' )

  has_many( :student_classes,
            :primary_key => 'dn',
            :foreign_key => 'puavoYearClass' )

  attr_accessor :student_class_ids

  before_validation :set_displayName_by_puavoClassNamingScheme, :set_cn
  after_save :manage_student_classes

  private

  def set_displayName_by_puavoClassNamingScheme
    naming_scheme = self.school.puavoClassNamingScheme
    name_block = eval "lambda { |class_number, start_year| \"" + naming_scheme + "\" }"
    number = Time.now.year - self.puavoSchoolStartYear.to_i + 1
    self.displayName = name_block.call( number, self.puavoSchoolStartYear )
  end

  def set_cn
    school = School.find(self.puavoSchool)
    self.cn = school[:cn] + "-" + I18n.t("activeldap.student_cn_prefix") + "-" + self.puavoSchoolStartYear.to_s
  end

  def manage_student_classes
    naming_scheme = '#{class_number}#{class_id} Class'
    name_block = eval "lambda { |class_number, class_id| \"" + naming_scheme + "\" }"
    class_number = Time.now.year - self.puavoSchoolStartYear.to_i + 1
    unless self.student_class_ids.nil?
      self.student_class_ids.each do |key, class_id|
        next if class_id.empty?
        next if self.student_classes.map{ |c| c.puavoClassId }.include?(class_id)
        StudentClass.create(:puavoClassId => class_id,
                            :puavoSchool => self.puavoSchool,
                            :puavoYearClass => self.dn.to_s,
                            :cn => self.cn + class_id.downcase, 
                            :displayName =>  name_block.call( class_number, class_id ))
      end
    end
    
    self.student_classes.each do |student_class|
      class_id = student_class.puavoClassId
      student_class.update_attributes( :puavoClassId => class_id,
                                       :puavoSchool => self.puavoSchool,
                                       :puavoYearClass => self.dn.to_s,
                                       :cn => self.cn + class_id.downcase, 
                                       :displayName =>  name_block.call( class_number, class_id ) )
    end
  end
end
