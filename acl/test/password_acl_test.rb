env = LDAPTestEnv.new

env.validate 'User password' do
  password_change_tests = [
    # student password change permissions
    lambda { student.can_set_password_for    student                        },
    lambda { student.cannot_set_password_for student2, LDAPTestEnvException },
    lambda { student.cannot_set_password_for other_school_student,
                                             LDAPTestEnvException },
    lambda { student.cannot_set_password_for teacher,  LDAPTestEnvException },
    lambda { student.cannot_set_password_for other_school_teacher,
                                             LDAPTestEnvException },
    lambda { student.cannot_set_password_for admin, LDAPTestEnvException },
    lambda { student.cannot_set_password_for other_school_admin,
                                             LDAPTestEnvException },
    lambda { student.cannot_set_password_for owner, LDAPTestEnvException },

    # teacher password change permissions
    lambda { teacher.can_set_password_for    teacher },
    lambda { teacher.can_set_password_for    student },
    lambda { teacher.cannot_set_password_for other_school_student,
                                             LDAPTestEnvException },
    lambda { teacher.cannot_set_password_for teacher2, LDAPTestEnvException },
    lambda { teacher.cannot_set_password_for other_school_teacher,
                                             LDAPTestEnvException },
    lambda { teacher.cannot_set_password_for admin, LDAPTestEnvException },
    lambda { teacher.cannot_set_password_for other_school_admin,
                                             LDAPTestEnvException },
    lambda { teacher.cannot_set_password_for owner, LDAPTestEnvException },

    # admin password change permissions
    lambda { admin.can_set_password_for admin   },
    lambda { admin.can_set_password_for student },
    lambda { admin.can_set_password_for teacher },
    lambda { admin.cannot_set_password_for owner, LDAPTestEnvException },
    lambda { admin.cannot_set_password_for other_school_student,
                                           LDAPTestEnvException },
    lambda { admin.cannot_set_password_for other_school_teacher,
                                           LDAPTestEnvException },
    lambda { admin.cannot_set_password_for other_school_admin,
                                           LDAPTestEnvException },

    # staff password change permissions
    lambda { staff.can_set_password_for staff },
    lambda { staff.cannot_set_password_for owner, LDAPTestEnvException },
    lambda { staff.cannot_set_password_for student, LDAPTestEnvException },
    lambda { staff.cannot_set_password_for teacher, LDAPTestEnvException },
    lambda { staff.cannot_set_password_for other_school_admin,
                                           LDAPTestEnvException },
    lambda { staff.cannot_set_password_for other_school_student,
                                           LDAPTestEnvException },
    lambda { staff.cannot_set_password_for other_school_teacher,
                                           LDAPTestEnvException },

    # organisation owner password change permissions
    # (not testing for owner --> owner because that would break "everything")
    lambda { owner.can_set_password_for staff },
    lambda { owner.can_set_password_for student },
    lambda { owner.can_set_password_for teacher },
    lambda { owner.can_set_password_for other_school_admin },
    lambda { owner.can_set_password_for other_school_student },
    lambda { owner.can_set_password_for other_school_teacher },

    # password management password change permissions
    lambda { pwmgmt.can_set_password_for student },
    lambda { pwmgmt.can_set_password_for teacher },
    lambda { pwmgmt.can_set_password_for admin   },
  ]

  password_change_tests.each do |test|
    reset
    test.call()
  end
end
