Feature: Manage users
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And I am logged in as "example" organisation owner

  Scenario: Add new oauth client
    Given I follow "OAuth clients"
    When I follow "New"
    Then I should see "New OAuth client"
    When I fill in "Name" with "Example software"
    And I fill in "Scope" with "read:personalInfo"
#    And I check "False"
    And I press "Create"
    Then I should see "Example software"
    And I should see "Client secret"
    And I should see "confidential"
    And I should not see "{SSHA}"

  Scenario: Delete oauth client
    Given the following oauth client:
      | displayName | userPassword    | puavoOAuthScope   |
      | client 1    | secretpassword1 | read:presonalInfo |
      | client 2    | secretpassword2 | read:presonalInfo |
      | client 3    | secretpassword3 | read:presonalInfo |
      | client 4    | secretpassword4 | read:presonalInfo |
    When I delete the 3rd oauth client
    Then I should see the following oauth clients:
      | Name     |
      | client 1 |
      | client 2 |
      | client 4 |

  Scenario: Edit OAuth client
    Given the following oauth client:
      | displayName | userPassword    | puavoOAuthScope   |
      | client 1    | secretpassword1 | read:presonalInfo |
      | client 2    | secretpassword2 | read:presonalInfo |
      | client 3    | secretpassword3 | read:presonalInfo |
      | client 4    | secretpassword4 | read:presonalInfo |
    And I follow "OAuth clients"
    And I follow "client 1"
    When I follow "Edit"
    Then I should see "Editing OAuth client"
    When I fill in "Name" with "Example software"
    And I fill in "Scope" with "read:personalInfo"
    And I press "Update"
    Then I should see "Example software"

  Scenario: List OAuth client
    Given the following oauth client:
      | displayName | userPassword    | puavoOAuthScope   |
      | client 1    | secretpassword1 | read:presonalInfo |
      | client 2    | secretpassword2 | read:presonalInfo |
      | client 3    | secretpassword3 | read:presonalInfo |
      | client 4    | secretpassword4 | read:presonalInfo |
    When I follow "OAuth clients"
    Then I should see the following oauth clients:
      | Name     |
      | client 1 |
      | client 2 |
      | client 3 |
      | client 4 |
