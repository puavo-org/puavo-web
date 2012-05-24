Feature: Authorize client
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new client name "unelmakoulu", 
    And I am on the login page
    When 

  Scenario: Non-existent user tries to change another user's password
    When I fill in "login[uid]" with "wrong"
    And I fill in "Password" with "pavelsecret"
    And I fill in "user[uid]" with "ben"
    And I fill in "New password" with "newbensecret"
    And I fill in "New password confirmation" with "newbensecret"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "Invalid password or username (wrong)"
