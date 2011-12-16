
Feature: Manage users
  In order to allow others to using all services
  As administrator
  I want to manage the set of users

  Background:
#    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
#    And a new role with name "Class 4" and which is joined to the "Class 4" group
#    And the following roles:
#    | displayName |
#    | Staff       |
#    And the following users:
#      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
#      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
#    And I am logged in as "cucumber" with password "cucumber"
    Given the following schools:
    | displayName      | cn            |
    | Example school 1 | exampleschool |
    And the following roles:
    | displayName | cn      | puavoEduPersonAffiliation |
    | Student     | student | student                   |
    | Teacher     | teacher | teacher                   |
    | Staff       | staff   | staff                     |
    And the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2011 | A                 | Example school 1 |
    |                 2010 | A,B,C             | Example school 1 |
    |                 2009 | A,B               | Example school 1 |
    |                 2008 |                   | Example school 1 |
    And I am logged in as "example" organisation owner
    And I follow "Example school 1"
    And I follow "Users"

  Scenario: Add new student to student year class
    Given I follow "New user"
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I check "Student"
    When I select "4. class" from "Student class"
    And I press "Create"
    Then I should not see "Failed to create user!"
    And I should see the following:
    |                       |
    | Mabey                 |
    | Ben                   |
    | ben                   |
    | 4. class              |
    And the memberUid should include "ben" on the "4. class" student year class
    And the member should include "ben" on the "4. class" student year class
    And the memberUid should include "ben" on the "Example school 1" school
    And the member should include "ben" on the "Example school 1" school
    And the memberUid should include "ben" on the "Domain Users" samba group
    And the member should include "ben" on the "Student" school role in the "Example school 1" school
    And the memberUid should include "ben" on the "Student" school role in the "Example school 1" school
    And the member should include "ben" on the "Student" role
    And the memberUid should include "ben" on the "Student" role
    And I should see the following special ldap attributes on the "User" object with "ben":
    | puavoEduPersonAffiliation | "^student$" |

  Scenario: Add new student to student class
    Given I follow "New user"
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I check "Student"
    And I press "Create"
    Then I should see "Student class can't be blank"
    And I should see "Failed to create user!"
    When I select "2C class" from "Student class"
    And I press "Create"
    Then I should not see "Failed to create user!"
    And I should see the following:
    |                       |
    | Mabey                 |
    | Ben                   |
    | ben                   |
    | 2C class              |
    And the memberUid should include "ben" on the "2C class" student class
    And the member should include "ben" on the "2C class" student class
    And the memberUid should include "ben" on the "2. class" student year class
    And the member should include "ben" on the "2. class" student year class
    And the memberUid should include "ben" on the "Example school 1" school
    And the member should include "ben" on the "Example school 1" school
    And the memberUid should include "ben" on the "Domain Users" samba group
    And the member should include "ben" on the "Student" school role in the "Example school 1" school
    And the memberUid should include "ben" on the "Student" school role in the "Example school 1" school
    And the member should include "ben" on the "Student" role
    And the memberUid should include "ben" on the "Student" role
    And I should see the following special ldap attributes on the "User" object with "ben":
    | puavoEduPersonAffiliation | "^student$" |

  Scenario: Add new teacher
    Given I follow "New user"
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I check "Teacher"
    And I press "Create"
    Then I should not see "Student class can't be blank"
    And I should not see "Failed to create user!"
    And I should see the following:
    |                       |
    | Mabey                 |
    | Ben                   |
    | ben                   |
    And the memberUid should include "ben" on the "Example school 1" school
    And the member should include "ben" on the "Example school 1" school
    And the memberUid should include "ben" on the "Domain Users" samba group
    And the member should include "ben" on the "Teacher" school role in the "Example school 1" school
    And the memberUid should include "ben" on the "Teacher" school role in the "Example school 1" school
    And the member should include "ben" on the "Teacher" role
    And the memberUid should include "ben" on the "Teacher" role
    And I should see the following special ldap attributes on the "User" object with "ben":
    | puavoEduPersonAffiliation | "^teacher$" |

  Scenario: Create new user
    Given I follow "New user"
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | user[mail][]              | ben.mabey@example.com |
    | user[telephoneNumber][]   | +35814123123123       |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    | Personel Number           | 556677                |
# FIXME test mail and telephoneNumber for more values  
#   | Group                      |       |
#   | Password                   |       |
#   | Password confirmation      |       |
#   | puavoEduPersonEntryYear    |       |
#   | puavoEduPersonEmailEnabled |       |
    # And set photo?
    And the "Language" select box should contain "Default"
    And the "Language" select box should contain "Finnish"
    And the "Language" select box should contain "Swedish"
    And I select "English" from "user[preferredLanguage]"
    And I select "2C class" from "Student class"
    And I check "Student"
#    # FIXME
#    And I choose "user_puavoAllowRemoteAccess_true"
#    And I attach the file at "features/support/test.jpg" to "image"
    And I press "Create"
    Then I should not see "Failed to create user!"
    And I should see the following:
    |                       |
    | Mabey                 |
    | Ben                   |
    | ben                   |
    | 2C class              |
    | ben.mabey@example.com |
    | +35814123123123       |
#    | Student               |
#    | English               |
#    | Yes                   |
#    | Mabey Ben             |
#    | 556677                |
    And the memberUid should include "ben" on the "2C class" student class
    And the member should include "ben" on the "2C class" student class
    And the memberUid should include "ben" on the "2. class" student year class
    And the member should include "ben" on the "2. class" student year class
    And the memberUid should include "ben" on the "Example school 1" school
    And the member should include "ben" on the "Example school 1" school
    And the memberUid should include "ben" on the "Domain Users" samba group
    And the member should include "ben" on the "Student" school role in the "Example school 1" school
    And the memberUid should include "ben" on the "Student" school role in the "Example school 1" school
    And the member should include "ben" on the "Student" role
    And the memberUid should include "ben" on the "Student" role
    When I follow "Edit"
    Then I should be on the edit user page
    When I follow "Cancel"
    Then I should be on the user page
    When I follow "Users"
    Then I should see "Mabey Ben"
    And I should see "ben"
    And I should see the following special ldap attributes on the "User" object with "ben":
    | puavoEduPersonAffiliation | "^student$" |

  Scenario: Create duplicate user to organisation
    Given the following users:
      | givenName | surname | uid | password | student_class | school           | roles   |
      | Ben       | Mabey   | ben | secret   | 2C class      | Example school 1 | Student |
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I check "Student"
    And I select "2C class" from "Student class"
    And I press "Create"
    Then I should see "Username has already been taken"
    Then I should see "Failed to create user!"

  Scenario: Create user with empty values
    Given the following users:
      | givenName | surname | uid | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben | secret   | 2C class      | Student | Example school 1 |
    And I am on the new user page
    And I press "Create"
    Then I should see "Failed to create user!"
    And I should see "Surname can't be blank"
    And I should see "Username can't be blank"
    And I should see "Roles can't be blank"

  Scenario: Create user with incorrect password confirmation
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey             |
    | Given name                | Ben               |
    | Username                  | ben               |
    | New password              | secretpw          |
    | New password confirmation | test confirmation |
    And I check "Student"
    And I select "2C class" from "Student class"
    And I press "Create"
    Then I should see "Failed to create user!"
    And I should see "New password doesn't match confirmation"

  Scenario: Change user role
    Given the following users:
      | givenName | surname | uid    | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben    | secret   | 2C class      | Student | Example school 1 |
    And I am on the edit user page with "ben"
    Then the id "role_exampleschool-student" checkbox should be checked
    And "2C class" should be selected for "user_student_class_id"
    When I select "Select" from "Student class"
    And I check "Teacher"
    And I uncheck "Student"
    And I press "Update"
    Then I should not see "User cannot be saved!"
    And the member should include "ben" on the "Teacher" school role in the "Example school 1" school
    And the memberUid should include "ben" on the "Teacher" school role in the "Example school 1" school
    And the member should not include "ben" on the "Student" school role in the "Example school 1" school
    And the memberUid should not include "ben" on the "Student" school role in the "Example school 1" school
    And the member should include "ben" on the "Teacher" role
    And the memberUid should include "ben" on the "Teacher" role
    And the member should not include "ben" on the "Student" role
    And the memberUid should not include "ben" on the "Student" role
    And the memberUid should not include "ben" on the "2C class" student class
    And the memberUid should not include "ben" on the "2. class" student year class
    And I should see the following special ldap attributes on the "User" object with "ben":
    | puavoEduPersonAffiliation | "^teacher$" |

  Scenario: Edit user
    Given the following users:
      | givenName | surname | uid    | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben    | secret   | 2C class      | Student | Example school 1 |
      | Joseph    | Wilk    | joseph | secret   | 2C class      | Student | Example school 1 |
    And I am on the edit user page with "ben"
    Then the id "role_exampleschool-student" checkbox should be checked
    When I fill in the following:
    | Surname    | MabeyEDIT |
    | Given name | BenEDIT   |
    | Username   | ben-edit   |
#   | Uid number                 |           |
#   | Home directory             |           |
#   | Email                      |           |
#   | Telephone number           |           |
#   | puavoEduPersonEntryYear    |           |
#   | puavoEduPersonEmailEnabled |           |
#   | Password                   |           |
#   | Password confirmation      |           |
    # And set photo?
#    And I select "Visitor" from "user[puavoEduPersonAffiliation]"
    And I select "3A class" from "Student class"
    And I check "Staff"
    And I press "Update"
    Then I should not see "User cannot be saved!"
    And I should see the following:
    |           |
    | MabeyEDIT |
    | BenEDIT   |
    | ben-edit  |
    | Staff     |
    And the memberUid should include "ben-edit" on the "3A class" student class
    And the member should include "ben-edit" on the "3A class" student class
    And the memberUid should include "ben-edit" on the "3. class" student year class
    And the member should include "ben-edit" on the "3. class" student year class
    And the memberUid should not include "ben" on the "2C class" student class
    And the memberUid should not include "ben" on the "2. class" student year class
    And the member should not include "ben-edit" on the "2. class" student year class
    And the member should not include "ben-edit" on the "2C class" student class
    And the member should include "ben-edit" on the "Staff" school role in the "Example school 1" school
    And the memberUid should not include "ben" on the "Staff" school role in the "Example school 1" school
    And the member should include "ben-edit" on the "Staff" role
    And the memberUid should include "ben-edit" on the "Staff" role
    And the memberUid should not include "ben" on the "Staff" role
    And the memberUid should include "ben-edit" on the "Example school 1" school
    And the memberUid should not include "ben" on the "Example school 1" school
    And the member should include "ben-edit" on the "Example school 1" school
    And the memberUid should include "ben-edit" on the "Domain Users" samba group
    And the memberUid should not include "ben" on the "Domain Users" samba group
    Given I am on the show user page with "joseph"
    And I should see "Joseph"
    And I should see "Wilk"
    And I should see "joseph"
    And I should not see "BenEDIT"
    And I should not see "MabeyEDIT"
    And I should not see "ben-edit"

  Scenario: Delete user
    Given the following users:
      | givenName | surname | uid    | password | student_class | roles   | school           | school_admin |
      | Ben       | Mabey   | ben    | secret   | 2C class      | Teacher | Example school 1 | true         |
      | Joseph    | Wilk    | joseph | secret   | 2C class      | Student | Example school 1 | false        |
    And I am on the show user page with "ben"
    # FIXME Is ben school admin?!
    When I follow "Remove"
    Then I should see "User was successfully removed."
    And the memberUid should not include "ben" on the "Example school 1" school
    And the "Example school 1" school not include incorret member values
    And the memberUid should not include "ben" on the "2. class" student year class
    And the memberUid should not include "ben" on the "2C class" student class
    And the memberUid should not include "ben" on the "Teacher" school role in the "Example school 1" school
    And the memberUid should not include "ben" on the "Teacher" role
    And the memberUid should not include "ben" on the "Domain Users" samba group
    And the "Example school 1" school not include incorret puavoSchoolAdmin values
    And the memberUid should not include "ben" on the "Domain Admins" samba group

  Scenario: Get user information in JSON
    Given the following users:
      | givenName | surname | uid    | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben    | secret   | 2C class      | Student | Example school 1 |
      | Joseph    | Wilk    | joseph | secret   | 2C class      | Student | Example school 1 |
      | Pavel     | Taylor  | pavel  | secret   | 2C class      | Staff   | Example school 1 |
    When I get on the show user JSON page with "ben"
    Then I should see JSON "{given_name: Ben, surname: Mabey, uid: ben}"
    When I get on the users JSON page with "Example school 1"
    Then I should see JSON "[{given_name: Ben, surname: Mabey, uid: ben},{given_name: Joseph, surname: Wilk, uid: joseph}, {given_name: Pavel, surname: Taylor, uid: pavel}]"

  Scenario: Check new user special ldap attributes
    Given the following users:
      | givenName | surname | uid | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben | secret   | 2C class      | Student | Example school 1 |
    Then I should see the following special ldap attributes on the "User" object with "ben":
    | sambaSID             | "^S-[-0-9+]"                   |
    | sambaAcctFlags       | "\[U\]"                        |
    | sambaPrimaryGroupSID | "^S-[-0-9+]"                   |
    | homeDirectory        | "/home/" + @school.cn + "/ben" |

  Scenario: Role selection does not lost when edit user and get error
    Given the following users:
      | givenName | surname | uid | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben | secret   | 2C class      | Student | Example school 1 |
    And I am on the edit user page with "ben"
    When I fill in "New password" with "some text"
    And I check "Staff"
    And I press "Update"
    Then I should see "New password doesn't match confirmation"
    And the id "role_exampleschool-staff" checkbox should be checked

  Scenario: Role selection does not lost when create new user and get error
    Given I follow "New user"
    When I fill in the following:
    | Surname    | Mabey |
    | Given name | Ben   |
    | Username   | ben   |
    And I check "Student"
    And I press "Create"
    Then I should see "Failed to create user!"
    And the id "role_exampleschool-student" checkbox should be checked

  Scenario: Student class selection does not lost when edit user and get error
    Given the following users:
      | givenName | surname | uid | password | student_class | roles   | school           |
      | Ben       | Mabey   | ben | secret   | 2C class      | Student | Example school 1 |
    And I am on the edit user page with "ben"
    Then "2C class" should be selected for "user_student_class_id"
    When I fill in "New password" with "some text"
    And I press "Update"
    Then I should see "New password doesn't match confirmation"
    And "2C class" should be selected for "user_student_class_id"

  Scenario: Student class selection does not lost when create new user and get error
    Given I follow "New user"
    When I fill in the following:
    | Surname    | Mabey |
    | Given name | Ben   |
    | Username   | ben   |
    And I select "2C class" from "Student class"
    And I press "Create"
    Then I should see "Failed to create user!"
    And "2C class" should be selected for "user_student_class_id"


  Scenario: Create new user with invalid username
    Given I follow "New user"
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | user[mail][]              | ben.mabey@example.com |
    | user[telephoneNumber][]   | +35814123123123       |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I select "2C class" from "Student class"
    And I check "Student"
    And I fill in "Username" with "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    And I press "Create"
    Then I should see "Username is too long (maximum is 255 characters)"
    When I fill in "Username" with "aa"
    And I press "Create"
    Then I should see "Username is too short (min is 3 characters)"
    When I fill in "Username" with "-ab"
    And I press "Create"
    Then I should see "Username must begin with the small letter"
    When I fill in "Username" with ".ab"
    And I press "Create"
    Then I should see "Username must begin with the small letter"
    When I fill in "Username" with "abc%&/()}]"
    And I press "Create"
    Then I should see "Username include invalid characters (allowed characters is a-z0-9.-)"
    When I fill in "Username" with "ben.Mabey"
    And I press "Create"
    Then I should see "Username include invalid characters (allowed characters is a-z0-9.-)"
    When I fill in "Username" with "ben-james.mabey"
    And I press "Create"
    Then I should see "User was successfully created."

  Scenario: Move user to another school
    Given the following schools:
    | displayName      | cn             |
    | Example school 2 | exampleschool2 |
    And the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2007 | A,B               | Example school 2 |
    Given the following users:
    | givenName | sn     | uid  | password | student_class | roles   | school           |
    | Joe       | Bloggs | joe  | secret   | 2C class      | Student | Example school 1 |
    | Jane      | Doe    | jane | secret   | 2C class      | Student | Example school 1 |
#    And "pavel" is a school admin on the "Example school 2" school
    And I am on the show user page with "jane"
    When I follow "Change school"
    And I select "Example school 2" from "new_school"
    And I press "Next"
    Then I should see "Select new student class"
    When I select "5B class" from "new_student_class"
    And I press "Change school"
    Then I should see "User(s) school has been changed!"
    And the sambaPrimaryGroupSID attribute should contain "Example school 2" of "jane"
    And the homeDirectory attribute should contain "Example school 2" of "jane"
    And the gidNumber attribute should contain "Example school 2" of "jane"
    And the puavoSchool attribute should contain "Example school 2" of "jane"
    And the memberUid should include "jane" on the "Example school 2" school
    And the member should include "jane" on the "Example school 2" school
    And the memberUid should not include "jane" on the "Example school 1" school
    And the member should not include "jane" on the "Example school 1" school
    And the memberUid should include "jane" on the "5B class" student class
    And the member should include "jane" on the "5B class" student class
    And the memberUid should include "jane" on the "5. class" student year class
    And the member should include "jane" on the "5. class" student year class
    And the memberUid should not include "jane" on the "2C class" student class
    And the memberUid should not include "jane" on the "2. class" student year class
    And the member should include "jane" on the "Student" school role in the "Example school 2" school
    And the memberUid should include "jane" on the "Student" school role in the "Example school 2" school
    And the memberUid should not include "jane" on the "Student" school role in the "Example school 1" school
    And the member should include "jane" on the "Student" role
    And the memberUid should include "jane" on the "Student" role
    
# FIXME
#  @allow-rescue
#  Scenario: Get user infromation in JSON from wrong school
#    Given a new school and group with names "School 2", "Class 8"
#    And the following users:
#     | given_names | lastname | login | group   | password | password_confirmation |
#     | Gerry       | Cheevers | gerry | Class 8 | secret   | secret                |
#    When I get on the show user JSON page with "gerry"
#    Then I should see "You are not allowed to access this action."
#    When I am on the new user_session page
#    And I am logged in as "gerry" with password "secret"
#    And I get on the show user JSON page with "pavel"
#    Then I should see "You are not allowed to access this action."

