Feature: User mass import
  In order to [goal]
  [stakeholder]
  wants [behaviour]
  
  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And a new role with name "Class 4" and which is joined to the "Class 4" group
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Class 4   | Staff                     |
    And I am logged in as "pavel" with password "secret"
 
  Scenario: Typical user mass import
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4	Student
    Joseph	Wilk	Class 4	Student
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should see the following users:
      | Ben    | Mabey | ben.mabey   | Class 4 | Student | OK |
      | Joseph | Wilk  | joseph.wilk | Class 4 | Student | OK |
    When I press "Create users"
    Then I should see "Users (2) was successfully created."
    And I should see "You can print users list to paper, download pdf-file."
    And the memberUid should include "ben.mabey" on the "Class 4" role
    And the member should include "ben.mabey" on the "Class 4" role
    And the memberUid should include "joseph.wilk" on the "Class 4" role
    And the member should include "joseph.wilk" on the "Class 4" role
    And the memberUid should include "ben.mabey" on the "School 1" school
    And the member should include "ben.mabey" on the "School 1" school
    And the memberUid should include "joseph.wilk" on the "School 1" school
    And the member should include "joseph.wilk" on the "School 1" school
    And the memberUid should include "ben.mabey" on the "Class 4" group
    And the member should include "ben.mabey" on the "Class 4" group
    And the memberUid should include "joseph.wilk" on the "Class 4" group
    And the member should include "joseph.wilk" on the "Class 4" group


  Scenario: User mass import when role is not defined
    Given I send to the following user mass import data
    """
    Ben	Mabey	Student
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "User type" from "users_import_columns[2]"
    And I press "Validates users"
    #Then I should see "Select the role you want to add users or start again and add the role to the user list"
    Then I should see "Following field value must be select when create new users:"
    And I should not see "User type"
    When I select "Class 4" from "user[role_ids]"
    And I press "Continue"
    Then I should see the following users:
      | Ben | Mabey | ben.mabey | Class 4 | Student | OK |
    When I press "Create users"
    Then I should see "Users (1) was successfully created."
    And I should see "You can print users list to paper, download pdf-file."

  Scenario: User mass import when user type is not defined
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Following field value must be select when create new users:"
    And I should not see "Role"
    And I select "Student" from "user[puavoEduPersonAffiliation]"
    And I press "Continue"
    Then I should see the following users:
      | Ben | Mabey | ben.mabey | Class 4 | Student | OK |
    When I press "Create users"
    Then I should see "Users (1) was successfully created."
    And I should see "You can print users list to paper, download pdf-file."

  Scenario: User mass import without given name or surname
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select field for each column"
    When I select "Username" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Given name and surname are required fields"
    When I select "Username" from "users_import_columns[0]"
    And I select "Given name" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Given name and surname are required fields"
    
  Scenario: User mass import with duplicate column name
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Given name" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Duplicate column name"
    
  Scenario: User mass import with case insensitive role name and user type
    Given I send to the following user mass import data
    """
    Ben	Mabey	cLaSs 4	sTuDeNt
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should not see "Role name is invalid"
    And I should not see "Roles can't be blank"
    And I should see the following users:
      | Ben | Mabey | ben.mabey | cLaSs 4 | Student | OK |

 Scenario: User mass import with invalid information
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 5	Some
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should see "The following new users of the data are not valid. Please repair the information and select revalidate button."
    And I should see "Role name is invalid"
    And I should not see "Roles can't be blank"
    And I should see "User type is invalid"
    And id the "users_import_invalid_list_2_" field should not contain "#<ActiveLdap"
    When I fill in "users_import_invalid_list_2_" with "Class 4"
    And I fill in "users_import_invalid_list_3_" with "Student"
    And I press "Revalidate"
    And I should see the following users:
      | Ben | Mabey | ben.mabey | Class 4 | OK |
    And I should not see "Roles can't be blank"
    And I should not see "User type is invalid"
 
  Scenario: Data does not lost with validation error case on user mass import
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4	Student
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Given name" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I fill in "users_import_raw_list_1_0" with "Wilk"
    And I press "Validates users"
    Then I should see "Duplicate column name"
    And id the "users_import_raw_list_1_0" field should not contain "Mabey"
    And id the "users_import_raw_list_1_0" field should contain "Wilk"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see the following users:
      | Ben | Wilk | ben.wilk | Class 4 | Student | OK |

  Scenario: Column selection does not lost with validation error case on user mass import
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select field for each column"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Given name" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Duplicate column name"
    And "Surname" should be selected for "users_import_columns_1"
