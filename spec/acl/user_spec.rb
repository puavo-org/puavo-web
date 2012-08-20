require 'spec_helper'
require 'acl_helper'


describe "User ACL" do

  ###
  # Connection setup
  # TODO: Hide to some helper
  ###

  before(:all) do

    test_organisation = Puavo::Organisation.find('example')
    default_ldap_configuration = ActiveLdap::Base.ensure_configuration
    # Setting up ldap configuration
    @ldap_host = test_organisation.ldap_host
    @ldap_base = test_organisation.ldap_base
    LdapBase.ldap_setup_connection( test_organisation.ldap_host,
                                    test_organisation.ldap_base,
                                    default_ldap_configuration["bind_dn"],
                                    default_ldap_configuration["password"] )
  end

  # Clear database after each "it" clause
  before(:each) do
    # Clean Up LDAP server: destroy all schools, groups and users
    User.all.each do |u|
      unless u.uid == "cucumber"
        u.destroy
      end
    end
    Group.all.each do |g|
      unless g.displayName == "Maintenance"
        g.destroy
      end
    end
    School.all.each do |s|
      unless s.displayName == "Administration"
        s.destroy
      end
    end
    Role.all.each do |p|
      unless p.displayName == "Maintenance"
        p.destroy
      end
    end
  end





  # Create school with students and teachers for each "it" clause
  before(:each) do

    school = School.create!(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    Role.create!(
      :displayName => "Class 4",
      :puavoSchool => school.dn
    )

    Role.create!(
      :displayName => "Staff",
      :puavoSchool => school.dn
    )

    @teacher = User.create!(
      :puavoSchool => school.dn,
      :givenName => "Severus",
      :sn => "Snape",
      :uid => "severus.snape",
      :role_name => "Staff",
      :new_password => "kala",
      :new_password_confirmation => "kala",
      :puavoEduPersonAffiliation => "Staff"
    )

    @admin = User.create!(
      :puavoSchool => school.dn,
      :givenName => "Minerva",
      :sn => "McGonagall",
      :uid => "minerva.mcgonagall",
      :role_name => "Staff",
      :new_password => "kala",
      :new_password_confirmation => "kala",
      :puavoEduPersonAffiliation => "Admin",
      :school_admin => true
    )
    school.add_admin(@admin)

    @student1 = User.create!(
      :puavoSchool => school.dn,
      :givenName => "Harry",
      :sn => "Potter",
      :mail => "harry@example.com",
      :uid => "harry.potter",
      :role_name => "Class 4",
      :new_password => "kala",
      :new_password_confirmation => "kala",
      :puavoEduPersonAffiliation => "Student"
    )

    @student2 = User.create!(
      :puavoSchool => school.dn,
      :givenName => "Ron",
      :mail => "ron@example.com",
      :sn => "Wesley",
      :uid => "ron.wesley",
      :role_name => "Class 4",
      :new_password => "kala",
      :new_password_confirmation => "kala",
      :puavoEduPersonAffiliation => "Student"
    )

  end


  # ACL tests
  #

  it "should not allow students to bind with bad password" do
    lambda {
      acl_user(@student1.dn, "badpassword")
    }.should raise_error(InsufficientAccessRights)
  end

  it "should not allow teachers to bind with bad password" do
    lambda {
      acl_user(@teacher.dn, "badpassword")
    }.should raise_error(InsufficientAccessRights)
  end

  it "should allow students to read their own attributes" do
    acl_user(@student1.dn, "kala") do |student|
      student.can_read @student1.dn, [:sn, :givenName]
    end
  end

  it "should allow students to read other students" do
    acl_user(@student1.dn, "kala") do |student|
      student.can_read @student2.dn, [:sn, :givenName]
    end
  end


  it "should not allow teachers to modify students" do
    acl_user(@teacher.dn, "kala") do |teacher|
      lambda {
        teacher.can_modify @student1.dn, [:replace, :givenName, ["newname"]]
      }.should raise_error(InsufficientAccessRights)
    end
  end

  it "should allow student to modify its own email" do
    acl_user(@student1.dn, "kala") do |student|
      student.can_modify @student1.dn, [:replace, :mail, ["foo@example.com"]]
    end
  end

  it "should not allow student to modify its own name" do
    acl_user(@student1.dn, "kala") do |student|
      lambda {
        student.can_modify @student1.dn, [:replace, :givenName, ["bad"]]
      }.should raise_error(InsufficientAccessRights)
    end
  end

  it "should not allow users to have same email addresses" do

    acl_user(@student1.dn, "kala") do |student|
      student.can_modify @student1.dn, [:replace, :mail, ["foo@example.com"]]
    end

    lambda {
      acl_user(@student2.dn, "kala") do |student|
        student.can_modify @student2.dn, [:replace, :mail, ["foo@example.com"]]
      end
    }.should raise_error(ConstraintViolation)

  end

  it "should not allow students to modify other students" do
    acl_user(@student1.dn, "kala") do |student|

      lambda {
        student.can_modify @student2.dn, [:replace, :givenName, ["newname"]]
      }.should raise_error(InsufficientAccessRights)

      lambda {
        student.can_modify @student2.dn, [:replace, :mail, ["bad@example.com"]]
      }.should raise_error(InsufficientAccessRights)

    end
  end

  it "should allow admins to modify students" do
    acl_user(@admin.dn, "kala") do |admin|
        admin.can_modify @student1.dn, [:replace, :givenName, ["newname"]]
    end
  end

  it "should allow students to change their own passwords" do
    acl_user(@student1.dn, "kala") do |admin|
      admin.set_password(@student1.dn, "kala2")
    end
  end

  it "should not allow students to change other's passwords" do
    acl_user(@student1.dn, "kala") do |admin|
      lambda {
        admin.set_password(@student2.dn, "kala2")
      }.should raise_error(LDAPException)
    end

  end

  it "should allow school admin to change student password" do
    acl_user(@admin.dn, "kala") do |admin|
      admin.set_password(@student1.dn, "kala2")
    end
  end

  it "should allow teacher to change student password" do
    acl_user(@teacher.dn, "kala") do |teacher|
      teacher.set_password(@student1.dn, "kala2")
    end
  end

end
