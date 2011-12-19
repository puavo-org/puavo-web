Feature: Manage passwords
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    # Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    # And a new role with name "Class 4" and which is joined to the "Class 4" group
    Given the following schools:
    | displayName      | cn            |
    | Example school 1 | exampleschool |
    And the following roles:
    | displayName | cn      | puavoEduPersonAffiliation |
    | Student     | student | student                   |
    | Teacher     | teacher | teacher                   |
    | Admin       | admin   | admin                     |
    And the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2008 | A                 | Example school 1 |
    And the following users:
    | givenName | sn     | uid   | password    | school_admin | roles   | student_class | school           |
    | Pavel     | Taylor | pavel | pavelsecret | true         | Admin   |               | Example school 1 |
    | Ben       | Mabey  | ben   | bensecret   | false        | Student | 4A class      | Example school 1 |
    And I am on the password change page

  Scenario: Non-existent user tries to change another user's password
    When I fill in "login[uid]" with "wrong"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "New password" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (wrong)"

  Scenario: Change the password of another user with an incorrect password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "wrong"
    And I fill in "user[uid]" with "ben"
    And I fill in "New password" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (pavel)"

  Scenario: Change the password of another user with an incorrect password confirmation
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "New password" with "newbensecret"
    And I fill in "New password confirmation" with "confirmation test"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "New password doesn't match confirmation"

  Scenario: Change to non-existent user password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "wrong"
    And I fill in "New password" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should see "User (wrong) does not exist"

  Scenario: Change to another user's password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "New password" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should see "Password change succesfully!"
    And I should not login with "ben" and "bensecret"
    And I should login with "ben" and "newbensecret"
    
  Scenario: User to change their own password
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "pavelsecret"
    And I fill in "New password" with "newpavelsecret"
    And I fill in "New password confirmation" with "newpavelsecret"
    And I press "Change password"
    Then I should see "Password change succesfully!"
    And I should not login with "pavel" and "pavelsecret"
    And I should login with "pavel" and "newpavelsecret"

  Scenario: User to change their own password with an incorrect password
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old Password" with "wrong"
    And I fill in "New password" with "newpavelsecret"
    And I fill in "New password confirmation" with "newpavelsecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (pavel)"

  Scenario: User to change their own password with an incorrect password confirmation
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old Password" with "pavelsecret"
    And I fill in "New password" with "newpavelsecret"
    And I fill in "New password confirmation" with "confirmation test"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "New password doesn't match confirmation"
    And I should not login with "pavel" and "newpavelsecret"
    And I should login with "pavel" and "pavelsecret"
