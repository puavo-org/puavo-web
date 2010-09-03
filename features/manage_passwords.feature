Feature: Manage passwords
  In order to [goal]
  [stakeholder]
  wants [behaviour]
  
  Scenario: Change user password
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And a new role with name "Class 4" and which is joined to the "Class 4" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
    | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
    | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    And I am on the password change page
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "secret"
    And I fill in "New password" with "new secret password"
    And I fill in "New password confirmation" with "confirmation test"
    And I press "Change password"
    Then I should not see "Password change succesfully!"
    And I should see "New password doesn't match confirmation"
    When I fill in "Username" with "pavel"
    And I fill in "Old password" with "secret"
    And I fill in "New password" with "new secret password"
    And I fill in "New password confirmation" with "new secret password"
    And I press "Change password"
    Then I should see "Password change succesfully!"
    When I am on the login page
    And I fill in "Login" with "pavel"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Login failed!"
    When I fill in "Login" with "pavel"
    And I fill in "Password" with "new secret password"
    And I press "Login"
    Then I should see "Login successful!"


