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
      | givenName | sn     | uid   | password | school_admin | role_name | eduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                |
    And I am logged in as "pavel" with password "secret"
  
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
# FIXME test mail and telephoneNumber for more values  
#   | Group                      |       |
#   | Password                   |       |
#   | Password confirmation      |       |
#   | puavoEduPersonEntryYear    |       |
#   | puavoEduPersonEmailEnabled |       |
    # And set photo?
    And I select "Student" from "user[eduPersonAffiliation]"
    And I check "Class 4" from roles
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
    And I should see "Class 4" on the "Groups by roles"
    And the memberUid should include "ben" on the "Class 4" group
    And the memberUid should include "ben" on the "Class 4" role
    And the user_member_uids should include "ben" on the "School 1" school
    And the user_members should include "ben" on the "School 1" school
    When I follow "Edit"
    Then I should be on the edit user page
    When I follow "Show"
    Then I should be on the user page

  Scenario: Edit user
    Given the following users:
      | givenName | surname | uid    | password | eduPersonAffiliation | role_name |
      | Ben       | Mabey   | ben    | secret   | alumn                | Class 4   |
      | Joseph    | Wilk    | joseph | secret   | alumn                | Class 4   |
    And the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    And I am on the edit user page with "ben"
    When I fill in the following:
    | Surname    | MabeyEDIT |
    | Given name | BenEDIT   |
    | Username   | benEDIT   |
#   | Uid number                 |           |
#   | Home directory             |           |
#   | Email                      |           |
#   | Telephone number           |           |
#   | puavoEduPersonEntryYear    |           |
#   | puavoEduPersonEmailEnabled |           |
#   | Password                   |           |
#   | Password confirmation      |           |
    # And set photo?
    And I select "Alumn" from "user[eduPersonAffiliation]"
    And I check "Staff" from roles
    And I press "Update"
    Then I should see the following:
    |           |
    | MabeyEDIT |
    | BenEDIT   |
    | benEDIT   |
    | Staff     |
    | Alumn     |
    And I should see "Class 4" on the "Groups by roles"
    And the memberUid should include "benEDIT" on the "Class 4" group
    And the memberUid should not include "ben" on the "Class 4" group
    And the memberUid should include "benEDIT" on the "Class 4" role
    And the memberUid should not include "ben" on the "Class 4" role
    And the user_member_uids should include "benEDIT" on the "School 1" school
    And the user_member_uids should not include "ben" on the "School 1" school
    And the user_members should include "benEDIT" on the "School 1" school
    And the user_members should not include "ben" on the "School 1" school
    Given I am on the show user page with "joseph"
    And I should see "Joseph"
    And I should see "Wilk"
    And I should see "joseph"
    And I should not see "BenEDIT"
    And I should not see "MabeyEDIT"
    And I should not see "benEDIT"

  Scenario: Delete user
    Given the following users:
      | givenName | surname | uid    | password | role_name | eduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | Class 4   | Student              |
      | Joseph    | Wilk    | joseph | secret   | Class 4   | Student              |
    And I am on the show user page with "ben"
    When I follow "Destroy"
    Then I should see "User was successfully destroyed."
    And the memberUid should not include "ben" on the "School 1" school
    And the "School 1" school not include incorret member values
    And the memberUid should not include "ben" on the "Class 4" group
    And the "Class 4" group not include incorret member values
    And the memberUid should not include "ben" on the "Class 4" role
    And the "Class 4" role not include incorret member values

  Scenario: Get user information in JSON
    Given the following users:
      | givenName | surname | uid    | password | role_name | eduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | Class 4   | Student              |
      | Joseph    | Wilk    | joseph | secret   | Class 4   | Student              |
    When I get on the show user JSON page with "ben"
    Then I should see JSON "user: {givenName: Ben, sn: Mabey, uid: ben}"

  Scenario: Check new user special ldap attributes
    Given the following users:
      | givenName | surname | uid | password | role_name | eduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | Class 4   | Student              |
    Then I should see the following special ldap attributes on the "User" object with "ben":
    | sambaSID             | "^S-[-0-9+]"                   |
    | sambaAcctFlags       | "\[U\]"                        |
    | sambaPrimaryGroupSID | "^S-[-0-9+]"                   |
    | homeDirectory        | "/home/" + @school.cn + "/ben" |

  Scenario: Role selection does not lost when edit user and get error
    Given the following users:
      | givenName | surname | uid    | password | eduPersonAffiliation | role_name |
      | Ben       | Mabey   | ben    | secret   | alumn                | Class 4   |
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

