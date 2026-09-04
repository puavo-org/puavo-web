Feature: Manage LDAP services
  In order to LDAP services can be use in Puavo LDAP-authentication
  Organisation owner should be able to
  add and remove System Accounts

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName               | cn        |
    | Football School of Trolls | fctrolls  |
    | Greenwich Steiner School  | greenwich |
    And I am logged in as "example" organisation owner

  Scenario: Add new organisation-wide LDAP service
    Given I follow "LDAP service"
    And I follow "New..." within "#pageContainer"
    When I fill in "Service Identifier" with "uid 1"
    And I fill in "Description" with "description 1"
    And I fill in "Password" with "password"
    And I check "LDAP bind (dn, uid)"
    And I check "getent passwd and group"
    And I check "access_all_schools"
    And I press "Create"
    Then I should see "Password is too short (min is 12 characters)"
    When I fill in "Password" with "secretpassword"
    And I press "Create"
    Then I should see "uid 1"
    And I should see "description 1"
    And I should not see "{SSHA}"
    And I should see "Bind DN"
    And I should see "uid=uid 1,ou=System Accounts,dc=edu,dc=example,dc=net"
    And I should see "LDAP bind (dn, uid)"
    And I should see "getent passwd and group"
    And I should see "Access all schools"
    And I should see "Yes"
    And I should bind "uid=uid 1,ou=System Accounts,dc=edu,dc=example,dc=net" with "secretpassword" to ldap

  Scenario: Delete organisation-wide LDAP service
    Given the following LDAP services:
      | uid   | description   | userPassword    | groups |
      | uid 1 | description 1 | secretpassword1 | auth   |
      | uid 2 | description 2 | secretpassword2 | auth   |
      | uid 3 | description 3 | secretpassword3 | getent |
      | uid 4 | description 4 | secretpassword4 | getent |
    When I delete the 3rd LDAP service
    Then I should see "LDAP service was successfully removed."
    Then I should see the following LDAP services:
      | Service Identifier | Description   |
      | uid 1              | description 1 |
      | uid 2              | description 2 |
      | uid 4              | description 4 |
    And "uid 3" is not member of "getent" system group

  Scenario: Edit organisation-wide LDAP service
    Given the following LDAP services:
      | uid   | description   | userPassword     | groups |
      | uid 1 | description 1 | secretpassword1 | auth   |
      | uid 2 | description 2 | secretpassword2 | auth   |
      | uid 3 | description 3 | secretpassword3 | auth   |
      | uid 4 | description 4 | secretpassword4 | auth   |
    And I follow "LDAP service"
    And I follow "uid 1"
    And I follow "Edit..."
    Then I should not see "{SSHA}"
    When I fill in "Description" with "test description one"
    And I check "getent passwd and group"
    And I press "Update"
    Then I should see "test description one"
    And I should see "uid=uid 1,ou=System Accounts,dc=edu,dc=example,dc=net"
    And I should see "LDAP bind (dn, uid)"
    And I should see "getent passwd and group"
    And I should see "Access all schools"
    And I should see "Yes"

  Scenario: Edit organisation-wide LDAP service and uncheck all system groups
    Given I follow "LDAP service"
    And I follow "New..." within "#pageContainer"
    When I fill in "Service Identifier" with "uid 1"
    And I fill in "Description" with "description 1"
    And I fill in "Password" with "secretpassword"
    And I check "LDAP bind (dn, uid)"
    And I check "getent passwd and group"
    And I press "Create"
    And I follow "Edit..."
    And I uncheck "getent passwd and group"
    And I uncheck "LDAP bind (dn, uid)"
    And I press "Update"
    And I should not see "LDAP bind (dn, uid)"
    And I should not see "getent passwd and group"

  Scenario: Get organisation information with organisation-wide LDAP service user
    Given the following LDAP services:
      | uid    | description   | userPassword    | groups  |
      | iivari | description 1 | secretpassword1 | orginfo |
    When I get the organisation JSON page with "service/iivari" and "secretpassword1"
    Then I should see JSON '{"preferred_language": "en", "domain": "example.puavo.net", "name": "Example Organisation"}'

  Scenario: Add new school-restricted LDAP service
    Given I follow "LDAP service"
    And I follow "New..." within "#pageContainer"
    When I fill in "Service Identifier" with "uid 2"
    And I fill in "Description" with "description 2"
    And I fill in "Password" with "secretpassword"
    And I check "Addressbook"
    And I uncheck "access_all_schools"
    And I check "Football School of Trolls"
    And I uncheck "Greenwich Steiner School"
    And I press "Create"
    Then I should see "uid 2"
    And I should see "description 2"
    And I should not see "{SSHA}"
    And I should see "Bind DN"
    And I should see "uid=uid 2,ou=System Accounts,dc=edu,dc=example,dc=net"
    And I should see "Addressbook"
    And I should see "Access all schools"
    And I should see "No"
    And I should see "Schools"
    And I should see "Football School of Trolls (fctrolls)"
    And I should not see "Greenwich Steiner School (greenwich)"
    And I should bind "uid=uid 2,ou=System Accounts,dc=edu,dc=example,dc=net" with "secretpassword" to ldap

  Scenario: Edit school-restricted LDAP service
    Given the following LDAP services:
      | uid   | description   | userPassword    | groups |
      | uid 7 | description 7 | secretpassword7 | auth   |
    And I follow "LDAP service"
    And I follow "uid 7"
    And I follow "Edit..."
    Then I should not see "{SSHA}"
    When I fill in "Description" with "test description seven"
    And I check "Addressbook"
    And I uncheck "access_all_schools"
    And I uncheck "Football School of Trolls"
    And I check "Greenwich Steiner School"
    And I press "Update"
    Then I should see "test description seven"
    And I should see "uid=uid 7,ou=System Accounts,dc=edu,dc=example,dc=net"
    And I should see "Addressbook"
    And I should see "Access all schools"
    And I should see "No"
    And I should see "Schools"
    And I should not see "Football School of Trolls (fctrolls)"
    And I should see "Greenwich Steiner School (greenwich)"
    And I follow "LDAP service"
    And I follow "uid 7"
    And I follow "Edit..."
    Then I should not see "{SSHA}"
    And I check "Football School of Trolls"
    And I press "Update"
    And I should see "uid=uid 7,ou=System Accounts,dc=edu,dc=example,dc=net"
    And I should see "Schools"
    And I should see "Football School of Trolls (fctrolls)"
    And I should see "Greenwich Steiner School (greenwich)"
