Feature: Manage servers
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new school and group with names "Example school 2", "Class 1" on the "example" organisation
    And the following servers:
    | puavoHostname | macAddress        |
    | someserver    | bc:5f:f4:56:59:71 |
    And I am logged in as "cucumber" with password "cucumber"

  Scenario: Edit server configuration
    Given I am on the server list page
    Then I should see "someserver"
    And I follow "someserver"
    And I follow "Edit..."
    And I fill in "Description" with "Example bootserver"
    And I fill in "Notes" with "Pretend there's something important here"
    And I check "Example school 2"
    And I press "Update"
    And I should see "Example school 2" within "#serverSchoolLimitBox"
    And I should see "Example bootserver"
    And I should see "Pretend there's something important here"

  Scenario: Check for unique server tags
    Given I am on the server list page
    Then I should see "someserver"
    And I follow "someserver"
    And I follow "Edit..."
    And I fill in "Tags" with "tagA tagB"
    And I press "Update"
    And I should see "tagA tagB"

  Scenario: Check that duplicate tags are removed
    Given I am on the server list page
    Then I should see "someserver"
    And I follow "someserver"
    And I follow "Edit..."
    And I fill in "Tags" with "tagA tagB tagB"
    And I press "Update"
    And I should see "tagA tagB"

  Scenario: Serial number validation check
    Given I am on the server list page
    Then I should see "someserver"
    And I follow "someserver"
    And I follow "Edit..."
    And I fill in "Serial number" with "ääääöööäääääööööö"
    And I press "Update"
    And I should see "Serial number contains invalid characters"

  Scenario: Hostname validation check
    Given I am on the server list page
    Then I should see "someserver"
    And I follow "someserver"
    And I follow "Edit..."
    And I fill in "Hostname" with "äasdöfäfäasdöfädsöfädf"
    And I press "Update"
    And I should see "Hostname contains invalid characters (allowed characters are: a-z0-9-)"

  Scenario: .img extension is removed from desktop image names
    Given I am on the server list page
    And I follow "someserver"
    And I follow "Edit..."
    And I fill in "Desktop Image" with "example_image.img"
    And I press "Update"
    # All "I should see" and "I should not see" checks are just simple
    # substring searches. If there's "example_image.img" on the page,
    # then it will match to "example_image". So we must check for the
    # absence of the extension itself.
    Then I should not see ".img"
    When I follow "Edit..."
    And I fill in "Desktop Image" with "example_image_2"
    And I press "Update"
    Then I should see "example_image_2"
