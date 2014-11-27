Feature: Manage passwords
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And a new role with name "Class 4" and which is joined to the "Class 4" group
    And the following roles:
    | displayName |
    | Teacher |
    | Student  |
    And the following users:
    | givenName | sn     | uid   | password    | school_admin | role_name | puavoEduPersonAffiliation | mail             |
    | Pavel     | Taylor | pavel | pavelsecret | true         | Teacher   | admin                     | pavel@foobar.com |
    | Ben       | Mabey  | ben   | bensecret   | false        | Class 4   | student                   | ben@foobar.com   |
    And I am on the password change page

  Scenario: Non-existent user tries to change another user's password
    When I fill in "login[uid]" with "wrong"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (wrong)"

  Scenario: Change the password of another user with an incorrect password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "wrong"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (pavel)"

  Scenario: Change the password of another user with an incorrect password confirmation
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "New password confirmation" with "confirmation test"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "New password doesn't match confirmation"

  Scenario: Change to non-existent user password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "wrong"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should see "User (wrong) does not exist"

  Scenario: Change to another user's password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should see "Password change succesfully!"
    And I should not login with "ben" and "bensecret"
    And I should login with "ben" and "newbensecret"
    
  Scenario: User to change their own password
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "pavelsecret"
    And I fill in "user[new_password]" with "newpavelsecret"
    And I fill in "New password confirmation" with "newpavelsecret"
    And I press "Change password"
    Then I should see "Password change succesfully!"
    And I should not login with "pavel" and "pavelsecret"
    And I should login with "pavel" and "newpavelsecret"

  Scenario: User to change their own password with an incorrect password
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "wrong"
    And I fill in "user[new_password]" with "newpavelsecret"
    And I fill in "New password confirmation" with "newpavelsecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (pavel)"

  Scenario: User to change their own password with an incorrect password confirmation
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "pavelsecret"
    And I fill in "user[new_password]" with "newpavelsecret"
    And I fill in "New password confirmation" with "confirmation test"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "New password doesn't match confirmation"
    And I should not login with "pavel" and "newpavelsecret"
    And I should login with "pavel" and "pavelsecret"

  Scenario: Forgot password
    Given mock password management service
    And I am on the forgot password page
    Then I should see "Please enter your email address to get instructions"
    When I fill in "Email" with "pavel@foobar.com"
    And I press "Continue"
    Then I should see "We've sent you an email that will allow you to reset your password."


  Scenario: Reset password by token url
    Given generate new token for "pavel"
    Given mock password management service
    And I am on the own password change by token page
    Then I should see "Reset your password"
    And I should see "Please enter your new password"
    When I fill in "Enter new password" with "foobar"
    And I fill in "Re-enter new password" with "foobar"
    And I press "Reset password"
    Then I should see "Your password has been reset successfully!"

  Scenario: Use forgot password form with invalid email
    Given mock password management service
    And I am on the forgot password page
    When I fill in "Email" with "broken@foobar.com"
    And I press "Continue"
    Then I should see "Couldn't find email: broken@foobar.com"

  Scenario: Reset password when password and password confirmation doesn't match
    Given generate new token for "pavel"
    And I am on the own password change by token page
    When I fill in "Enter new password" with "foobar"
    And I fill in "Re-enter new password" with "barfoo"
    And I press "Reset password"
    Then I should see "New password doesn't match confirmation"
