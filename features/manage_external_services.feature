Feature: Manage external services
  In order to external services can be use in Puavo LDAP-authentication
  Organisation owner should be able to
  add and remove System Accounts

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And I am logged in as "example" organisation owner

  
  Scenario: Add new external service
    Given I follow "External service"
    And I follow "New"
    When I fill in "Service Identifier" with "uid 1"
    And I fill in "Description" with "description 1"
    And I fill in "Password" with "password"
    And I check "Services that have only minimal information needed for ldap simple binds (dn, uid)"
    And I check "Services that have access to all information needed for getent"
    And I press "Create"
    Then I should see "Password is too short (min is 12 characters)"
    When I fill in "Password" with "secretpassword"
    And I press "Create"
    Then I should see "uid 1"
    And I should see "description 1"
    And I should not see "{SSHA}"
    And I should see "Bind DN"
    And I should see "uid=uid 1,ou=System Accounts,dc=edu,dc=example4,dc=fi"
    And I should see "Services that have only minimal information needed for ldap simple binds (dn, uid)"
    And I should see "Services that have access to all information needed for getent"
    And I should bind "uid=uid 1,ou=System Accounts,dc=edu,dc=example4,dc=fi" with "secretpassword" to ldap

  Scenario: Delete external service
    Given the following external services:
      | uid   | description   | userPassword    | groups |
      | uid 1 | description 1 | secretpassword1 | auth   |
      | uid 2 | description 2 | secretpassword2 | auth   |
      | uid 3 | description 3 | secretpassword3 | getent |
      | uid 4 | description 4 | secretpassword4 | getent |
    When I delete the 3rd external service
    Then I should see the following external services:
      | Service Identifier | Description   |
      | uid 1              | description 1 |
      | uid 2              | description 2 |
      | uid 4              | description 4 |
    And "uid 3" is not member of "getent" system group

  Scenario: Edit external service
    Given the following external services:
      | uid   | description   | userPassword     | groups |
      | uid 1 | description 1 | sercretpassword1 | auth   |
      | uid 2 | description 2 | sercretpassword2 | auth   |
      | uid 3 | description 3 | sercretpassword3 | auth   |
      | uid 4 | description 4 | sercretpassword4 | auth   |
    And I follow "External service"
    And I follow "uid 1"
    And I follow "Edit"
    Then I should not see "{SSHA}"
    When I fill in "Description" with "test description one"
    And I check "Services that have access to all information needed for getent"
    And I press "Update"
    Then I should see "test description one"
    And I should see "uid=uid 1,ou=System Accounts,dc=edu,dc=example4,dc=fi"
    And I should see "Services that have only minimal information needed for ldap simple binds (dn, uid)"
    And I should see "Services that have access to all information needed for getent"


  Scenario: Edit external service and unceck all system groups
    Given I follow "External service"
    And I follow "New"
    When I fill in "Service Identifier" with "uid 1"
    And I fill in "Description" with "description 1"
    And I fill in "Password" with "secretpassword"
    And I check "Services that have only minimal information needed for ldap simple binds (dn, uid)"
    And I check "Services that have access to all information needed for getent"
    And I press "Create"
    And I follow "Edit"
    And I uncheck "Services that have access to all information needed for getent"
    And I uncheck "Services that have only minimal information needed for ldap simple binds (dn, uid)"
    And I press "Update"
    And I should not see "Services that have only minimal information needed for ldap simple binds (dn, uid)"
    And I should not see "Services that have access to all information needed for getent"

  Scenario: Get groups information with external service users
    Given the following external services:
      | uid   | description   | userPassword    | groups |
      | uid 1 | description 1 | secretpassword1 | auth   |
      | uid 2 | description 2 | secretpassword2 | auth   |
      | uid 3 | description 3 | secretpassword3 | getent |
