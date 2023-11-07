Feature: Test enforced email addresses in an organisation
  In order to allow others to using all services
  As administrator
  I want to manage the set of users

  Background:
    Given a new school with names "School 1" on the "example" organisation
    And the following users:
      | givenName | sn     | uid      | password | school_admin | mail        | puavoEduPersonAffiliation |
      | Example   | User 1 | example1 |          | false        | foo@bar.com | testuser                  |
      | Example   | User 2 | example2 |          | false        |             | testuser                  |
      | Admin     | Admin  | admin    | secret   | true         |             | admin                     |
    And I am logged in as "cucumber" with password "cucumber"

  @automatic_email
  Scenario: Creating a new user will automatically set the email address
    Given I am on the new user page
    # The email input box must not exist at all
    Then I should not see element "user[mail][]"
    When I fill in the following:
    | Surname                   | Example               |
    | Given name                | User                  |
    | Username                  | example3              |
    And I should see "Email (automatic)"
    And I check "Test user"
    And I press "Create"
    Then I should see "example3@hogwarts.magic" within "#contactInformation"

  @automatic_email
  Scenario: Editing an existing user will (re)set the email address
    # Test 1 (already has an email address)
    Given I am on the edit user page with "example1"
    Then I should not see element "user[mail][]"
    And I should see "foo@bar.com"
    Then I press "Update"
    And I should see "example1@hogwarts.magic" within "#contactInformation"
    # Test 2 (no email address at all)
    Given I am on the edit user page with "example2"
    Then I should not see element "user[mail][]"
    And I press "Update"
    Then I should see "example2@hogwarts.magic" within "#contactInformation"

  @automatic_email
  Scenario: Changing the username will also update the email address
    Given I am on the new user page
    Then I should not see element "user[mail][]"
    When I fill in the following:
    | Surname                   | Example               |
    | Given name                | User                  |
    | Username                  | example3              |
    And I should see "Email (automatic)"
    And I check "Test user"
    And I press "Create"
    Then I should see "example3@hogwarts.magic" within "#contactInformation"
    Then I am on the edit user page with "example3"
    And I fill in "Username" with "foobar"
    And I press "Update"
    Then I should see "foobar@hogwarts.magic" within "#contactInformation"
