Feature: Manage external passwords
  Testing that users in the "heroes" organisation can change passwords
  through the external login mechanism.  Users do not need to be
  setup in "example"-organisation, but as a side-effect of password
  changes they will be created there.  Users "sarah.connor" and "peter.parker"
  do exist in the "heroes"-organisation, and "charlie.agent" and "david.agent"
  do not.

  Background:
    Given a new school and group with names "School 1", "Class 1" on the "example" organisation
    And a new role with name "Class 1" and which is joined to the "Class 1" group
    And the following roles:
    | displayName |
    | Teacher     |
    | Student     |
    And the following users:
    | givenName | sn     | uid           | password      | school_admin | role_name | puavoEduPersonAffiliation | mail                |
    | Charlie   | Agent  | charlie.agent | charliesecret | true         | Teacher   | admin                     | charlie@example.com |
    | David     | Agent  | david.agent   | davidsecret   | false        | Class 1   | student                   | david@example.com   |
    And I am on the password change page

  Scenario: External user fails to change own password with bad credentials
    Given I am on the own password change page
    When I fill in "Username" with "sarah.connor"
    And I fill in "Old password" with "wrong"
    And I fill in "user[new_password]" with "newsecret"
    And I fill in "New password confirmation" with "newsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (sarah.connor)"

  Scenario: External user changes their own password
    Given I am on the own password change page
    When I fill in "Username" with "sarah.connor"
    And I fill in "Old password" with "secret"
    And I fill in "user[new_password]" with "newsecret"
    And I fill in "New password confirmation" with "newsecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "sarah.connor" and "secret"
    And I should login with "sarah.connor" and "newsecret"

  Scenario: External user changes their own password with another user form
    Given I am on the password change page
    When I fill in "login[uid]" with "peter.parker"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "peter.parker"
    And I fill in "user[new_password]" with "newsecret"
    And I fill in "New password confirmation" with "newsecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "peter.parker" and "secret"
    And I should login with "peter.parker" and "newsecret"

  Scenario: External user tries to change password without permissions
    Given I am on the password change page
    When I fill in "login[uid]" with "peter.parker"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "sarah.connor"
    And I fill in "user[new_password]" with "newsarahconnorsecret"
    And I fill in "New password confirmation" with "newsarahconnorsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Can't change password to upstream service."

  Scenario: Change the password of another user with correct permissions
    Given I am on the password change page
    When I fill in "login[uid]" with "sarah.connor"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "peter.parker"
    And I fill in "user[new_password]" with "newpeterparkersecret"
    And I fill in "New password confirmation" with "newpeterparkersecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "peter.parker" and "secret"
    And I should login with "peter.parker" and "newpeterparkersecret"
