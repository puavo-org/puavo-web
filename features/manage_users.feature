
Feature: Manage users
  In order to allow others to using all services
  As administrator
  I want to manage the set of users

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following users:
      | givenName | sn     | uid        | password | school_admin | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel      | secret   | true         | admin                     |
      | Admin     | User   | admin      | secret   | true         | admin                     |
      | Admin     | Super  | superadmin | secret   | true         | admin                     |
    And I am logged in as "cucumber" with password "cucumber"

  Scenario: Non-owners should not see user deletion buttons on user show pages
    # Part 1: an admin user does NOT see the delete link
    Given I am logged in as "admin" with password "secret"
    And I am on the show user page with "admin"
    Then I should see:
      """
      This user is an administrator of the school "School 1"
      """
    And I should not see "The user is an owner of this organisation"
    And I should not see "Delete user"

    # Part 2: an owner user DOES see the delete link
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the show user page with "admin"
    Then I should see:
      """
      This user is an administrator of the school "School 1"
      """
    And I should not see "The user is an owner of this organisation"
    And I should see "Delete user"

  Scenario: You should not be able to delete yourself or mark yourself for deletion
    Given I am logged in as "admin" with password "secret"
    And I am on the show user page with "admin"
    And I should not see "Mark for deletion"
    And I should not see "Delete user"

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
    | user[new_password]        | secretpw              |
    | Confirm new password      | secretpw              |
    | Personnel Number          | 556677                |
    | SSH public key            | ssh-rsa Zm9vYmFy      |   # the key is "foobar" in base64
# FIXME test mail and telephoneNumber for more values
#   | Group                      |       |
#   | Password                   |       |
#   | Password confirmation      |       |
#   | puavoEduPersonEntryYear    |       |
#   | puavoEduPersonEmailEnabled |       |
    # And set photo?
    And I check "Student"
    And the "Language" select box should contain "Default"
    And the "Language" select box should contain "Finnish"
    And the "Language" select box should contain "Swedish \(Finland\)"
    And the "Language" select box should contain "English \(United States\)"
    And the "Language" select box should contain "German \(Switzerland\)"
    And I select "English (United States)" from "Language"
    # FIXME
    And I choose "user_puavoAllowRemoteAccess_true"
    And I attach the file at "features/support/test.jpg" to "Image"
    And I select group "Class 4"
    And I press "Create"
    Then I should see the following:
    |                                                 |
    | Mabey                                           |
    | Ben                                             |
    | ben                                             |
    | Class 4                                         |
    | ben.mabey@example.com                           |
    | +35814123123123                                 |
    | Student                                         |
    | English (United States)                         |
    | Yes                                             |
    | 556677                                          |
    | 38:58:f6:22:30:ac:3c:91:5f:30:0c:66:43:12:c6:3f |
    And I should see image of "ben"
    And the memberUid should include "ben" on the "Class 4" group
    And the member should include "ben" on the "Class 4" group
    And the memberUid should include "ben" on the "School 1" school
    And the member should include "ben" on the "School 1" school
    And the memberUid should include "ben" on the "Domain Users" samba group
    When I follow "Edit..."
    Then I am on the edit user page with "ben"
    When I follow "Cancel"
    Then I am on the show user page with "ben"
    #When I follow "Users" within ".navbarFirstLevel"
    When I follow "Users" within "#pageContainer #tabs .first"
    Then I should see "Mabey Ben"
    And I should see "ben"
    And I should see "Student"
    And I should see the following special ldap attributes on the "User" object with "ben":
    | preferredLanguage      | "en" |
    And I should not see "The user is an admin of this school"
    And I should not see "The user is an owner of this organisation"

  Scenario: Create duplicate user to organisation
    Given the following users:
      | givenName | surname | uid | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | student                   |
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | Username                  | ben                   |
    | user[new_password]        | secretpw              |
    | Confirm new password      | secretpw              |
    And I check "Student"
    And I press "Create"
    Then I should see "Username has already been taken"
    Then I should see "Failed to create the user!"

  Scenario: Create user with empty values
    Given the following users:
      | givenName | surname | uid | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | student                   |
    And I am on the new user page
    And I press "Create"
    Then I should see "Failed to create the user!"
    And I should see "Given name can't be blank"
    And I should see "Surname can't be blank"
    And I should see "Username can't be blank"
    And I should see "Role can't be blank"

  Scenario: Create user with incorrect password confirmation
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey             |
    | Given name                | Ben               |
    | Username                  | ben               |
    | user[new_password]        | secretpw          |
    | Confirm new password      | test confirmation |
    And I check "Student"
    And I press "Create"
    Then I should see "Failed to create the user!"
    And I should see "New password doesn't match the confirmation"

  Scenario: Edit user
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | visitor                   |
      | Joseph    | Wilk    | joseph | secret   | visitor                   |
    And the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    # Set the teaching group directly before opening the edit page, otherwise
    # the group is not selected and saving the form will remove the user from
    # the group
    And I add user "ben" to teaching group "Class 4"
    And I am on the edit user page with "ben"
    When I fill in the following:
    | Surname    | MabeyEDIT       |
    | Given name | BenEDIT         |
    | Username   | ben-edit        |
    | Email      | ben@example.com |
#   | Uid number                 |           |
#   | Telephone number           |           |
#   | puavoEduPersonEntryYear    |           |
#   | puavoEduPersonEmailEnabled |           |
#   | Password                   |           |
#   | Password confirmation      |           |
    # And set photo?
    And I check "Visitor"
    And I attach the file at "features/support/test.jpg" to "Image"
    And I press "Update"
    Then I should see the following:
    |                 |
    | MabeyEDIT       |
    | BenEDIT         |
    | ben-edit        |
    | Class 4         |
    | Visitor         |
    | ben@example.com |
    And I should see image of "ben-edit"
    And the memberUid should include "ben-edit" on the "Class 4" group
    And the member should include "ben-edit" on the "Class 4" group
    And the memberUid should not include "ben" on the "Class 4" group
    And the memberUid should include "ben-edit" on the "School 1" school
    And the memberUid should not include "ben" on the "School 1" school
    And the member should include "ben-edit" on the "School 1" school
    And the memberUid should include "ben-edit" on the "Domain Users" samba group
    And the memberUid should not include "ben" on the "Domain Users" samba group
    When I follow "Edit..."
    And I fill in "Given name" with "BenEDIT2"
    And I press "Update"
    Then I should see "User was successfully updated."
    Given I am on the show user page with "joseph"
    And I should see "Joseph"
    And I should see "Wilk"
    And I should see "joseph"
    And I should not see "BenEDIT"
    And I should not see "MabeyEDIT"
    And I should not see "ben-edit"
    And I should not see "The user is an admin of this school"
    And I should not see "The user is an owner of this organisation"

  Scenario: Can't use "-" as a telephone number (new)
    Given I am on the new user page
    Then I fill in the following:
    | Surname                   | Donald                |
    | Given name                | Duck                  |
    | Username                  | donald.duck           |
    | user[telephoneNumber][]   | -                     |
    And I check "Test user"
    And I press "Create"
    Then I should see "Failed to create the user!"
    And I should see "Telephone number is invalid"

  Scenario: Can't use "-" as a telephone number (edit)
    Given I am on the new user page
    Then I fill in the following:
    | Surname                   | Donald                |
    | Given name                | Duck                  |
    | Username                  | donald.duck           |
    And I check "Test user"
    And I press "Create"
    Then I am on the edit user page with "donald.duck"
    And I fill in the following:
    | user[telephoneNumber][]   | -                     |
    And I press "Update"
    And I should see "Telephone number is invalid"

  Scenario: Listing users
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | visitor                   |
      | Joseph    | Wilk    | joseph | secret   | visitor                   |
    And the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    When I follow "School 1" within "#left"
    And I follow "Users" within "#pageContainer"
    Then I should see "Mabey Ben" within "#pageContainer"
    And I should not see /\["ben"\]/
    And I should not see "PuavoEduPersonAffiliation"

  Scenario: Delete user
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation | school_admin |
      | Ben       | Mabey   | ben    | secret   | admin                     | true         |
      | Joseph    | Wilk    | joseph | secret   | student                   | false        |
    And I am on the show user page with "ben"
    When I follow "Delete user"
    Then I should see "User was successfully removed."
    And the memberUid should not include "ben" on the "School 1" school
    And the "School 1" school not include incorrect member values
    And the memberUid should not include "ben" on the "Class 4" group
    And the "Class 4" group not include incorrect member values
    And the memberUid should not include "ben" on the "Domain Users" samba group
    And the "School 1" school not include incorrect puavoSchoolAdmin values
    And the memberUid should not include "ben" on the "Domain Admins" samba group

  Scenario: Get user information in JSON
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | student                   |
      | Joseph    | Wilk    | joseph | secret   | student                   |
    When I get on the show user JSON page with "ben"
    Then I should see JSON '{"given_name": "Ben", "surname": "Mabey", "uid": "ben"}'
    When I get on the users JSON page with "School 1"
    Then I should see JSON '[{"given_name": "Admin", "surname": "User", "uid": "admin"},{"given_name": "Admin", "surname": "Super", "uid": "superadmin"},{"given_name": "Ben", "surname": "Mabey", "uid": "ben"},{"given_name": "Joseph", "surname": "Wilk", "uid": "joseph"}, {"given_name": "Pavel", "surname": "Taylor", "uid": "pavel"}]'

  Scenario: Check new user special ldap attributes
    Given the following users:
      | givenName | surname | uid | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben | secret   | student                   |
    Then I should see the following special ldap attributes on the "User" object with "ben":
    | sambaSID             | "^S-[-0-9+]"                   |
    | sambaAcctFlags       | "\[U\]"                        |
    | sambaPrimaryGroupSID | "^S-[-0-9+]"                   |

  Scenario: Create new user with invalid username
    Given the following groups:
    | displayName | cn      | puavoEduGroupType |
    | Class 6B    | class6b | teaching group    |
    And I am on the new user page
    When I fill in the following:
    | Surname                   | Mabey                 |
    | Given name                | Ben                   |
    | user[mail][]              | ben.mabey@example.com |
    | user[telephoneNumber][]   | +35814123123123       |
    | user[new_password]        | secretpw              |
    | Confirm new password      | secretpw              |
    And I check "Student"
    And I fill in "Username" with "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    And I press "Create"
    Then I should see "Username is too long (maximum is 255 characters)"
    When I fill in "Username" with "aa"
    And I press "Create"
    Then I should see "Username is too short (min is 3 characters)"
    When I fill in "Username" with "-ab"
    And I press "Create"
    Then I should see "Username must begin with a small letter"
    When I fill in "Username" with ".ab"
    And I press "Create"
    Then I should see "Username must begin with a small letter"
    When I fill in "Username" with "abc%&/()}]"
    And I press "Create"
    Then I should see "Username contains invalid characters (allowed characters are a-z0-9.-)"
    When I fill in "Username" with "ben.Mabey"
    And I press "Create"
    Then I should see "Username contains invalid characters (allowed characters are a-z0-9.-)"
    When I fill in "Username" with "ben-james.mabey"
    And I select group "Class 6B"
    And I press "Create"
    Then I should see the following:
    | Ben             |
    | Mabey           |
    | ben-james.mabey |
    | +35814123123123 |
    | Class 6B        |

  Scenario: Lock user
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Ben       | Mabey   | ben    | secret   | visitor                   |
      | Joseph    | Wilk    | joseph | secret   | visitor                   |
    And the following groups:
    | displayName | cn      |
    | Class 6B    | class6b |
    And I am on the edit user page with "ben"
    When I check "User is locked"
    And I press "Update"
    Then I should see "User is locked"

  Scenario: Create user with invalid SSH public key
    Given I am on the new user page
    When I fill in the following:
    | Surname        | Doe      |
    | Given name     | Jane     |
    | Username       | jane.doe |
    | SSH public key | foobar   |
    And I check "Student"
    And I select group "Class 4"
    And I press "Create"
    Then I should see "Jane"
    And I should see "Doe"
    And I should see "Invalid public key"

  Scenario: Give the user a non-image file as the image
    Given I am on the new user page
    When I fill in the following:
    | Surname        | Doe      |
    | Given name     | Jane     |
    | Username       | jane.doe |
    And I attach the file at "features/support/hello.txt" to "Image"
    And I press "Create"
    Then I should see "Failed to save the image"

  Scenario: Give the user an invalid email address
    Given I am on the new user page
    When I fill in the following:
    | Surname        | Doe      |
    | Given name     | Jane     |
    | Username       | jane.doe |
    | user[mail][]              | foo<html>@bar.äää |
    And I press "Create"
    Then I should see "The email address is not valid."

  Scenario: Email addresses are trimmed
    Given I am on the new user page
    When I fill in the following:
    | Surname        | Donald                  |
    | Given name     | Duck                    |
    | Username       | donald.duck             |
    And I fill in "Email" with " donald.duck@calisota.us "
    And I check "Student"
    And I select group "Class 4"
    And I press "Create"
    And I should see "donald.duck@calisota.us"

  Scenario: Prevent user deletion
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Donald    | Duck    | donald | 313      | visitor                   |
    Then I am on the show user page with "donald"
    And I should see "Delete user"
    And I should see "Prevent deletion"
    When I follow "Prevent deletion"
    Then I should see "User deletion has been prevented."
    And I should see "This user cannot be deleted"
    And I should not see "Prevent deletion"
    And I should not see "Delete user"

  Scenario: Mark user for deletion
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Donald    | Duck    | donald | 313      | visitor                   |
    Then I am on the show user page with "donald"
    And I should see "Delete user"
    And I should see "Mark for deletion"
    #
    When I follow "Mark for deletion"
    Then I should see "This user has been marked for deletion"
    And I should see "Remove deletion marking"
    And I should not see "Mark for deletion"
    And I should see "Delete user"
    #
    When I follow "Remove deletion marking"
    Then I should see "User is no longer marked for deletion"
    And I should not see "This user has been marked for deletion"
    And I should see "Mark for deletion"

  Scenario: Prevent the deletion of a user who has already been marked for deletion
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Donald    | Duck    | donald | 313      | visitor                   |
    Then I am on the show user page with "donald"
    #
    When I follow "Mark for deletion"
    Then I should see "This user has been marked for deletion"
    And I should see "User is locked"
    #
    When I follow "Prevent deletion"
    Then I should see "User deletion has been prevented."
    And I should see "This user cannot be deleted"
    And I should not see "This user has been marked for deletion"
    And I should not see "Prevent deletion"
    And I should not see "Delete user"
    And I should not see "User is locked"

  Scenario: Trying to lock a non-deletable user will not succeed
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Donald    | Duck    | donald | 313      | visitor                   |
    Then I am on the show user page with "donald"
    When I follow "Prevent deletion"
    Then I should see "User deletion has been prevented."
    And I should see "This user cannot be deleted"
    And I should not see "User is locked"
    When I follow "Edit..."
    Then I am on the edit user page with "donald"
    And I fill in "Surname" with "Ducky"
    And I check "User is locked"
    And I press "Update"
    Then I should see "User was successfully updated."
    And I should see "Donald Ducky"
    And I should not see "User is locked"

  Scenario: Preventing user deletion must clear existing deletion marks
    Given the following users:
      | givenName | surname | uid    | password | puavoEduPersonAffiliation |
      | Donald    | Duck    | donald | 313      | visitor                   |
    Then I am on the show user page with "donald"
    When I follow "Mark for deletion"
    Then I should see "This user has been marked for deletion"
    And I should see "User is locked"
    And I should see "Prevent deletion"
    When I follow "Prevent deletion"
    Then I should see "User deletion has been prevented."
    And I should see "This user cannot be deleted"
    And I should not see "User is locked"
    And I should not see "Prevent deletion"
    And I should not see "Delete user"

  # It tooke me almost an hour to write this test. I hope it never has to be changed.
  Scenario: Removing the admin role removes the user from school admins and organisation owners
    # create an admin user
    Given I am on the new user page
    When I fill in the following:
    | Given name | Thomas   |
    | Surname    | Anderson |
    | Username   | neo      |
    And I check "Teacher"
    And I check "Admin"
    And I press "Create"
    Then I should not see "The user is an administrator of the school"
    And I should not see "The user is an owner of this organisation"
    # make them an owner and an admin
    When I follow "Owners"
    Then I should see "Thomas Anderson (neo) School 1" within "#availableAdmins"
    And I follow "Add" on the "Thomas Anderson" user
    Then I should see "Thomas Anderson is now an owner of this organisation"
    And I should see "Thomas Anderson (neo) School 1" within "#currentOwners"
    And I should not see "Thomas Anderson (neo) School 1" within "#availableAdmins"
    Then I am on the school page with "School 1"
    When I follow "Admins"
    Then I should see "Thomas Anderson (neo) (Organisation owner) School 1" within "#other_admin_users"
    And I follow "Add" on the "Thomas Anderson" user
    Then I should see "Thomas Anderson (School 1) is now an admin user"
    And I should see "Thomas Anderson (neo) (Organisation owner) School 1" on the school admin list
    Then I am on the show user page with "neo"
    And I should see:
      """
      This user is an administrator of the school "School 1"
      """
    And I should see "The user is an owner of this organisation"
    # then remove the admin role
    Then I am on the edit user page with "neo"
    And I uncheck "puavoEduPersonAffiliation_admin"
    And I press "Update"
    Then I should see "User was successfully updated."
    # verify everything
    Then I should not see "The user is an administrator of the school"
    And I should not see "The user is an owner of this organisation"
    When I follow "Owners"
    Then I should not see "Thomas Anderson (neo) School 1" within "#currentOwners"
    And I should not see "Thomas Anderson (neo) School 1" within "#availableAdmins"
    Then I am on the school page with "School 1"
    When I follow "Admins"
    Then I should not see "Thomas Anderson (neo) School 1" within "#this_school_admin_users"
    And I should not see "Thomas Anderson (neo) School 1" within "#other_admin_users"

  Scenario: A few verified email address tests
    Given "pavel" has verified email addresses
    Then I am on the show user page with "pavel"
    Then I should see "address1@example.com (verified)"
    And I should see "address2@example.com (verified, primary address)"
    And I should not see "address3@example.com (verified)"
    Then I am on th edit user page with "pavel"
    And I should see "This user has verified email addresses. They cannot be edited nor removed."
    # TODO: Test that the fields are read-only


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
