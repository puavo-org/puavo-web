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

  def self.classes_by_school(school)
    self.find( :all,
               :attribute => 'puavoSchool',
               :value => school.dn.to_s ).inject([]) do |result, student_year_class|
      # Return only student year class if student classes not found
      # If student year class include subclass (StudentClass) return only all student classes.
      # Year class can be a user's main group only if subclasses (StudentClass) can not be found
      if student_year_class.student_classes.empty?
        result.push(student_year_class)
      else
        result += student_year_class.student_classes
      end
      result
    end
  end

  # If any student class not found by member then try to find member's student year class.
  # Student classes is not defined on the small school.
  def self.find_first_by_member(member)
    StudentClass.find( :first,
                       :attribute => "member",
                       :value => member ) or
      StudentYearClass.find( :first,
                             :attribute => "member",
                             :value => member )
  end

  def self.find_by_puavoId(puavoId)
    StudentClass.find( :first,
                       :attribute => "puavoId",
                       :value => puavoId ) or
      StudentYearClass.find( :first,
                             :attribute => "puavoId",
                             :value => puavoId )
  end

  def validate
    unless self.puavoSchoolStartYear.to_s =~ /^[0-9]+$/
      errors.clear
      errors.add( :puavoSchoolStartYear, I18n.t("invalid_characters",
                                                :scope => "activeldap.errors.messages.student_year_class") )
    end

    unless self.student_class_ids.nil?
      self.student_class_ids.each do |key, class_id|
        if class_id.length > 11
          errors.add( :student_classes,
                      I18n.t("activeldap.errors.messages.too_long",
                             :attribute => I18n.t("puavoClassId",
                                                  :scope => "activeldap.attributes.student_class."),
                             :count => 11) )
          break
        end
      end
    end
  end

  private

  def set_displayName_by_puavoClassNamingScheme
    # FIXME
    type_of_year_class_name = LdapOrganisation.current.puavoClassNamingType rescue "default"
    # FIXME
    number = Time.now.year - self.puavoSchoolStartYear.to_i + 1
    self.displayName = I18n.t( "student_year_class_naming_scheme_#{type_of_year_class_name}",
                               :locale => LdapOrganisation.current.preferredLanguage,
                               :start_year => self.puavoSchoolStartYear,
                               :class_number => number )

  end

  def set_cn
    school = School.find(self.puavoSchool)
    self.cn = school[:cn] + "-" + self.puavoSchoolStartYear.to_s
  end

  def manage_student_classes
    # FIXME
    type_of_class_name = "default"
    # FIXME
    class_number = Time.now.year - self.puavoSchoolStartYear.to_i + 1
    unless self.student_class_ids.nil?
      self.student_class_ids.each do |key, class_id|
        next if class_id.empty?
        student_class_data = { 
          :puavoClassId => class_id,
          :puavoSchool => self.puavoSchool,
          :puavoYearClass => self.dn.to_s,
          :cn => self.cn + class_id.downcase, 
          :displayName => I18n.t( "student_class_naming_scheme_#{type_of_class_name}",
                                  :locale => LdapOrganisation.current.preferredLanguage,
                                  :class_id => class_id.upcase,
                                  :class_number => class_number )
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
