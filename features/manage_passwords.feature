Feature: Manage passwords
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following users:
    | givenName | sn     | uid   | password    | school_admin | puavoEduPersonAffiliation | mail             |
    | Pavel     | Taylor | pavel | pavelsecret | true         | admin                     | pavel@foobar.com |
    | Ben       | Mabey  | ben   | bensecret   | false        | student                   | ben@foobar.com   |
    And I am on the password change page

  Scenario: Empty own password change form should not crash
    Given I am on the own password change page
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "You did not fill in all the required form fields."

  Scenario: Username is remembered on the own password change form
    Given I am on the own password change page
    When I fill in "login[uid]" with "huey.duck"
    And I press "Change password"
    Then the "login[uid]" field should contain "huey.duck"
    And I should see "Invalid password or username"
    And I should not see "Password changed successfully!"

  Scenario: Initial (own) username is set and remembered
    Given I am on the own password change page with changing user dewey.duck
    Then the "login[uid]" field should contain "dewey.duck"
    And I press "Change password"
    Then the "login[uid]" field should contain "dewey.duck"
    And I should see "Invalid password or username"

  Scenario: Empty other user password change form should not crash
    Given I am on the password change page
    When I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "You did not fill in all the required form fields."

  Scenario: Initial changing and changed usernames are set and remembered
    Given I am on the password change page with changing user donald.duck and changed user louie.duck
    Then the "login[uid]" field should contain "donald.duck"
    And the "user[uid]" field should contain "louie.duck"
    When I press "Change password"
    Then the "login[uid]" field should contain "donald.duck"
    And the "user[uid]" field should contain "louie.duck"
    And I should see "Invalid password or username"

  Scenario: Non-existent user tries to change another user's password
    When I fill in "login[uid]" with "wrong"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "Confirm new password" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (wrong)"

  Scenario: Change the password of another user with an incorrect password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "wrong"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "Confirm new password" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (pavel)"

  Scenario: Change the password of another user with an incorrect password confirmation
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "Confirm new password" with "confirmation test"
    And I wait 11 seconds
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Password doesn't match the confirmation"

  Scenario: Change to non-existent user password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "wrong"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "Confirm new password" with "newbensecret"
    And I press "Change password"
    Then I should see "User (wrong) does not exist"

  Scenario: Change to another user's password
    When I fill in "login[uid]" with "pavel"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "user[new_password]" with "newbensecret"
    And I fill in "Confirm new password" with "newbensecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "ben" and "bensecret"
    And I should login with "ben" and "newbensecret"

  Scenario: User to change their own password
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "pavelsecret"
    And I fill in "user[new_password]" with "newpavelsecret"
    And I fill in "Confirm new password" with "newpavelsecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "pavel" and "pavelsecret"
    And I should login with "pavel" and "newpavelsecret"

  Scenario: User to change their own password with an incorrect password
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "wrong"
    And I fill in "user[new_password]" with "newpavelsecret"
    And I fill in "Confirm new password" with "newpavelsecret"
    And I wait 11 seconds
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (pavel)"

  Scenario: User to change their own password with an incorrect password confirmation
    Given I am on the own password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "pavelsecret"
    And I fill in "user[new_password]" with "newpavelsecret"
    And I fill in "Confirm new password" with "confirmation test"
    And I wait 11 seconds
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Password doesn't match the confirmation"
    And I should not login with "pavel" and "newpavelsecret"
    And I should login with "pavel" and "pavelsecret"

  Scenario: Forgot password
    Given mock password management service
    And I am on the forgot password page
    Then I should see "Reset your password Please enter your email address and we'll send you a link that allows"
    When I fill in "Email" with "pavel@foobar.com"
    And I press "Continue"
    Then I should see "We've sent you an email that will let you reset your password."


  Scenario: Reset password by token url
    Given generate new token for "pavel"
    Given mock password management service
    And I am on the own password change by token page
    Then I should see "Reset your password"
    And I should see "Please enter your new password"
    When I fill in "Enter new password" with "foobar"
    And I fill in "Re-enter new password" with "foobar"
    And I press "Reset password"
    Then I should see "Your password has been successfully reset"

  Scenario: Use forgot password form with invalid email
    Given mock password management service
    And I am on the forgot password page
    When I fill in "Email" with "broken@foobar.com"
    And I press "Continue"
    Then I should see "We've sent you an email that will let you reset your password."

  Scenario: Reset password when password and password confirmation doesn't match
    Given generate new token for "pavel"
    And I am on the own password change by token page
    When I fill in "Enter new password" with "foobar"
    And I fill in "Re-enter new password" with "barfoo"
    And I press "Reset password"
    Then I should see "Password doesn't match the confirmation"
