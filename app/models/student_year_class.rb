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

  attr_accessor :student_class_ids, :student_class_puavo_ids

  before_validation :set_displayName_by_puavoClassNamingScheme, :set_cn
  after_save :manage_student_classes

  def validate
    unless self.puavoSchoolStartYear.to_s =~ /^[0-9]+$/
      errors.clear
      errors.add( :puavoSchoolStartYear, I18n.t("invalid_characters",
                                                :scope => "activeldap.errors.messages.student_year_class") )
    end

    unless self.student_class_ids.nil?
      self.student_class_ids.each do |key, class_id|
        if class_id.length > 7
          errors.add( :student_classes,
                      I18n.t("activeldap.errors.messages.too_long",
                             :attribute => I18n.t("puavoClassId",
                                                  :scope => "activeldap.attributes.student_class."),
                             :count => 7) )
          break
        end
      end
    end
  end

  private

  def set_displayName_by_puavoClassNamingScheme
    naming_scheme = self.school.puavoClassNamingScheme
    name_block = eval "lambda { |class_number, start_year| \"" + naming_scheme + "\" }"
    number = Time.now.year - self.puavoSchoolStartYear.to_i + 1
    self.displayName = name_block.call( number, self.puavoSchoolStartYear )
  end

  def set_cn
    school = School.find(self.puavoSchool)
    self.cn = school[:cn] + "-" + I18n.t("activeldap.student_cn_prefix")[0..2] + "-" + self.puavoSchoolStartYear.to_s
  end

  def manage_student_classes
    # FIXME
    naming_scheme = '#{class_number}#{class_id} Class'
    name_block = eval "lambda { |class_number, class_id| \"" + naming_scheme + "\" }"
    class_number = Time.now.year - self.puavoSchoolStartYear.to_i + 1
    unless self.student_class_ids.nil?
      self.student_class_ids.each do |key, class_id|
        next if class_id.empty?
        student_class_data = { 
          :puavoClassId => class_id,
          :puavoSchool => self.puavoSchool,
          :puavoYearClass => self.dn.to_s,
          :cn => self.cn + class_id.downcase, 
          :displayName =>  name_block.call( class_number, class_id )
        }
        if self.student_class_puavo_ids && self.student_class_puavo_ids[key]
          # Update exists student class
          StudentClass.find(self.student_class_puavo_ids[key]).update_attributes(student_class_data)
        else
          # Create new student class
          StudentClass.create(student_class_data)
        end
      end
    end
  end

  def validate_on_create
    # cn attribute must be unique on the ou=Groups branch
    # cn == group name (posix group)
    groups = self.search_groups_by_cn
    unless groups.empty?
      errors.add( :puavoSchoolStartYear, 
                  I18n.t("activeldap.errors.messages.taken",
                         :attribute => I18n.t("puavoSchoolStartYear",
                                              :scope => "activeldap.attributes.student_year_class") ) )
    end
  end
  
  def validate_on_update
    groups = self.search_groups_by_cn
    if !groups.empty? && groups.first[:puavoId].to_s != self.puavoId.to_s
      errors.add( :puavoSchoolStartYear, 
                  I18n.t("activeldap.errors.messages.taken",
                         :attribute => I18n.t("puavoSchoolStartYear",
                                              :scope => "activeldap.attributes.student_year_class") ) )
    end

  end
end
