
Feature: Manage users
  In order to allow others to using all services
  As administrator
  I want to manage the set of users

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And a new role with name "Class 4" and which is joined to the "Class 4" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    And I am logged in as "cucumber" with password "cucumber"
  
  Scenario: Create new user
    Given the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    And I am on the new user page
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
    And I select "Student" from "user[puavoEduPersonAffiliation]"
    And the "Language" select box should contain "Default"
    And the "Language" select box should contain "Finnish"
    And the "Language" select box should contain "Swedish"
    And I select "English" from "user[preferredLanguage]"
    And I check "Class 4" from roles
    # FIXME
    And I choose "user_puavoAllowRemoteAccess_true"
    And I attach the file at "features/support/test.jpg" to "image"
    And I press "Create"
    Then I should see the following:
    |                       |
    | Mabey                 |
    | Ben                   |
    | ben                   |
    | Class 4               |
    | ben.mabey@example.com |
    | +35814123123123       |
    | Student               |
    | English               |
    | Yes                   |
    | Mabey Ben             |
    | 556677                |
    And I should see "Class 4" on the "Groups by roles"
    And the memberUid should include "ben" on the "Class 4" group
    And the member should include "ben" on the "Class 4" group
    And the memberUid should include "ben" on the "Class 4" role
    And the member should include "ben" on the "Class 4" role
    And the memberUid should include "ben" on the "School 1" school
    And the member should include "ben" on the "School 1" school
    And the memberUid should include "ben" on the "Domain Users" samba group
    When I follow "Edit"
    Then I should be on the edit user page
    When I follow "Cancel"
    Then I should be on the user page
    When I follow "Users"
    Then I should see "Mabey Ben"
    And I should see "ben"
    And I should see "Student"

  Scenario: Create duplicate user to organisation
    Given the following users:
      | givenName | surname | uid | password | role_name | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | Class 4   | Student                   |
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I select "Student" from "user[puavoEduPersonAffiliation]"
    And I check "Class 4" from roles
    And I press "Create"
    Then I should see "Username has already been taken"
    Then I should see "Failed to create user!"

  Scenario: Create user with empty values
    Given the following users:
      | givenName | surname | uid | password | role_name | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | Class 4   | Student                   |
    And I am on the new user page
    And I press "Create"
    Then I should see "Failed to create user!"
    And I should see "Surname can't be blank"
    And I should see "Username can't be blank"
    And I should see "User type is invalid"
    And I should see "Roles can't be blank"

  Scenario: Create user with incorrect password confirmation
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey             |
    | Given name                | Ben               |
    | Username                  | ben               |
    | New password              | secretpw          |
    | New password confirmation | test confirmation |
    And I select "Student" from "user[puavoEduPersonAffiliation]"
    And I check "Class 4" from roles
    And I press "Create"
    Then I should see "Failed to create user!"
    And I should see "New password doesn't match confirmation"

  Scenario: Edit user
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation | role_name |
      | Ben       | Mabey   | ben    | secret   | visitor                   | Class 4   |
      | Joseph    | Wilk    | joseph | secret   | visitor                   | Class 4   |
    And the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    And I am on the edit user page with "ben"
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
    And I select "Visitor" from "user[puavoEduPersonAffiliation]"
    And I check "Staff" from roles
    And I press "Update"
    Then I should see the following:
    |           |
    | MabeyEDIT |
    | BenEDIT   |
    | ben-edit   |
    | Staff     |
    | Visitor |
    And I should see "Class 4" on the "Groups by roles"
    And the memberUid should include "ben-edit" on the "Class 4" group
    And the member should include "ben-edit" on the "Class 4" group
    And the memberUid should not include "ben" on the "Class 4" group
    And the memberUid should include "ben-edit" on the "Class 4" role
    And the member should include "ben-edit" on the "Class 4" role
    And the memberUid should not include "ben" on the "Class 4" role
    And the memberUid should include "ben-edit" on the "School 1" school
    And the memberUid should not include "ben" on the "School 1" school
    And the member should include "ben-edit" on the "School 1" school
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
      | givenName | surname | uid    | password | role_name | puavoEduPersonAffiliation | school_admin |
      | Ben       | Mabey   | ben    | secret   | Class 4   | Admin                     | true         |
      | Joseph    | Wilk    | joseph | secret   | Class 4   | Student                   | false        |
    And I am on the show user page with "ben"
    When I follow "Destroy"
    Then I should see "User was successfully destroyed."
    And the memberUid should not include "ben" on the "School 1" school
    And the "School 1" school not include incorret member values
    And the memberUid should not include "ben" on the "Class 4" group
    And the "Class 4" group not include incorret member values
    And the memberUid should not include "ben" on the "Class 4" role
    And the "Class 4" role not include incorret member values
    And the memberUid should not include "ben" on the "Domain Users" samba group
    And the "School 1" school not include incorret puavoSchoolAdmin values
    And the memberUid should not include "ben" on the "Domain Admins" samba group

  Scenario: Get user information in JSON
    Given the following users:
      | givenName | surname | uid    | password | role_name | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | Class 4   | Student                   |
      | Joseph    | Wilk    | joseph | secret   | Class 4   | Student                   |
    When I get on the show user JSON page with "ben"
    Then I should see JSON "{given_name: Ben, surname: Mabey, uid: ben}"
    When I get on the users JSON page with "School 1"
    Then I should see JSON "[{given_name: Ben, surname: Mabey, uid: ben},{given_name: Joseph, surname: Wilk, uid: joseph}, {given_name: Pavel, surname: Taylor, uid: pavel}]"

  Scenario: Check new user special ldap attributes
    Given the following users:
      | givenName | surname | uid | password | role_name | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | Class 4   | Student                   |
    Then I should see the following special ldap attributes on the "User" object with "ben":
    | sambaSID             | "^S-[-0-9+]"                   |
    | sambaAcctFlags       | "\[U\]"                        |
    | sambaPrimaryGroupSID | "^S-[-0-9+]"                   |
    | homeDirectory        | "/home/" + @school.cn + "/ben" |

  Scenario: Role selection does not lost when edit user and get error
    Given the following users:
      | givenName | surname | uid | password | puavoEduPersonAffiliation | role_name |
      | Ben       | Mabey   | ben | secret   | visitor                   | Class 4   |
    And I am on the edit user page with "ben"
    When I fill in "New password" with "some text"
    And I check "Staff" from roles
    And I press "Update"
    Then I should see "New password doesn't match confirmation"
    And the id "role_staff" checkbox should be checked

  Scenario: Role selection does not lost when create new user and get error
    Given I am on the new user page
    When I fill in the following:
    | Surname    | Mabey |
    | Given name | Ben   |
    | Username   | ben   |
    And I check "Class 4" from roles
    And I press "Create"
    Then I should see "User type is invalid"
    And the id "role_class_4" checkbox should be checked

  Scenario: Create new user with invalid username
    Given the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | user[mail][]              | ben.mabey@example.com |
    | user[telephoneNumber][]   | +35814123123123       |
    | New password              | secretpw              |
    | New password confirmation | secretpw              |
    And I select "Student" from "user[puavoEduPersonAffiliation]"
    And I check "Class 4" from roles
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
    Given the following users:
    | givenName | sn     | uid  | password | role_name | puavoEduPersonAffiliation |
    | Joe       | Bloggs | joe  | secret   | Class 4   | Student                   |
    | Jane      | Doe    | jane | secret   | Class 4   | Student                   |
    And a new school and group with names "Example school 2", "Class 5" on the "example" organisation
    And a new role with name "Class 5" and which is joined to the "Class 5" group
    And "pavel" is a school admin on the "Example school 2" school
    And I am on the show user page with "jane"
    When I follow "Change school"
    And I select "Example school 2" from "new_school"
    And I press "Next"
    Then I should see "Select new role"
    When I select "Class 5" from "new_role"
    And I press "Change school"
    Then I should see "User(s) school has been changed!"
    And the sambaPrimaryGroupSID attribute should contain "Example school 2" of "jane"
    And the homeDirectory attribute should contain "Example school 2" of "jane"
    And the gidNumber attribute should contain "Example school 2" of "jane"
    And the puavoSchool attribute should contain "Example school 2" of "jane"
    And the memberUid should include "jane" on the "Example school 2" school
    And the member should include "jane" on the "Example school 2" school
    And the memberUid should not include "jane" on the "School 1" school
    And the member should not include "jane" on the "School 1" school
    And the memberUid should include "jane" on the "Class 5" group
    And the member should include "jane" on the "Class 5" group
    And the memberUid should not include "jane" on the "Class 4" group
    And the member should not include "jane" on the "Class 4" group
    And the memberUid should include "jane" on the "Class 5" role
    And the member should include "jane" on the "Class 5" role
    And the memberUid should not include "jane" on the "Class 4" role
    And the member should not include "jane" on the "Class 4" role
    
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

