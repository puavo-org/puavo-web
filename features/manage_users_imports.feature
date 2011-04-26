Feature: User mass import
  In order to [goal]
  [stakeholder]
  wants [behaviour]
  
  Background:
    Given a new school and group with names "School 2", "Class 5" on the "example" organisation
    And a new role with name "Class 5" and which is joined to the "Class 5" group
    And a new school and group with names "School 1", "Class 4" on the "example" organisation
    And a new role with name "Class 4" and which is joined to the "Class 4" group
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Class 4   | Staff                     |
    And "pavel" is a school admin on the "School 2" school
    And I am logged in as "pavel" with password "secret"
 
  Scenario: Typical user mass import
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4	Student
    Joseph	Wilk	Class 4	Student
    """
    Then I should see "Select correct name of column for each data"
    And I should see "Ben"
    And I should see "Wilk"
    And I should see "Class 4"
    And I should see "Student"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should see the following users:
      | Ben    | Mabey | ben.mabey   | Class 4 | Student |
      | Joseph | Wilk  | joseph.wilk | Class 4 | Student |
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
    And the memberUid should include "ben.mabey" on the "Domain Users" samba group
    And the memberUid should include "joseph.wilk" on the "Domain Users" samba group
    When I follow the PDF link "download pdf-file."
    Then I should see "Name: Ben Mabey"
    And I should see "Username: ben.mabey"
    And I should see "Name: Joseph Wilk"
    And I should see "Username: joseph.wilk"
    And I should see "Password"

  Scenario: User mass import when create failed
    When I send to the following user mass import data
    """
    Ben	Mabey	Class 4	Student
    Joseph	Wilk	Class 4	Student
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should see the following users:
      | Ben    | Mabey | ben.mabey   | Class 4 | Student |
      | Joseph | Wilk  | joseph.wilk | Class 4 | Student |
    When I cut nextPuavoId value by one
#    And the following users:
#    | givenName | surname | uid | password | role_name | puavoEduPersonAffiliation |
#    | Jim       | Jones   | jim | secret   | Class 4   | Student                   |
    And I press "Create users"
#    Then I should see "All users was not successfully created!"
#    And I should see "Successful: 1"
#    And I should see "Failed: 1"
#    And I should see "You can print users list to paper, download pdf-file."
#    When I follow the PDF link "download pdf-file."
#    Then I should see "Name: Ben Mabey"
#    And I should see "Username: ben.mabey"
#    And I should see "Password"


  Scenario: User mass import when role is not defined
    Given I send to the following user mass import data
    """
    Ben	Mabey	Student
    Ben Karl	Mabey	Student
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "User type" from "users_import_columns[2]"
    And I press "Validates users"
    #Then I should see "Select the role you want to add users or start again and add the role to the user list"
    Then I should see "Following field value must be select when create new users:"
    And I should not see "User type"
    And I can not select "Class 5" from the "user_role_name"
    When I select "Class 4" from "user[role_name]"
    And I press "Continue"
    #Then I should see "Username has already been taken"
    #And "Class 4" should be selected for "users_import_invalid_list_3_0"
    #And I can not select "Class 5" from the "users_import_invalid_list_3_0"
    #When I fill in "users_import_invalid_list_0_0" with "Ben Karl"
    #And I fill in "users_import_invalid_list_4_0" with "benk.mabey"
    #And I press "Revalidate"
    Then I should see the following users:
      | Ben      | Mabey | Class 4 | Student | ben.mabey  |
      | Ben Karl | Mabey | Class 4 | Student | benkarl.mabey |
    When I press "Create users"
    Then I should see "Users (2) was successfully created."
    And I should see "You can print users list to paper, download pdf-file."
    When I follow the PDF link "download pdf-file."
    Then I should see "Name: Ben Mabey"
    And I should see "Username: ben.mabey"
    And I should see "Password"
    And I should see "Name: Ben Karl Mabey"
    And I should see "Username: benkarl.mabey"

  Scenario: User mass import when role is not defined and select empty role value
    Given I send to the following user mass import data
    """
    Ben	Mabey	Student
    Ben Karl	Mabey	Student
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "User type" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Following field value must be select when create new users:"
    And I should not see "User type"
    When I press "Continue"
    Then I should see "Following field value must be select when create new users:"
    When I press "Continue"
    Then I should see "Following field value must be select when create new users:"
    When I select "Class 4" from "user[role_name]"
    And I press "Continue"
#    And I press "Revalidate"
#    Then I should see "Username has already been taken"
#    And I should not see "Role Role"
#    When I fill in "users_import_invalid_list_0_0" with "Ben Karl"
#    And I fill in "users_import_invalid_list_4_0" with "benk.mabey"
#    And I press "Revalidate"
    Then I should see the following users:
      | Ben      | Mabey | Class 4 | Student | ben.mabey  |
      | Ben Karl | Mabey | Class 4 | Student | benkarl.mabey |
    When I press "Create users"
    Then I should see "Users (2) was successfully created."
    And I should see "You can print users list to paper, download pdf-file."
    When I follow the PDF link "download pdf-file."
    Then I should see "Name: Ben Mabey"
    And I should see "Username: ben.mabey"
    And I should see "Password"
    And I should see "Name: Ben Karl Mabey"
    And I should see "Username: benkarl.mabey"

  Scenario: User mass import when user type is not defined
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Following field value must be select when create new users:"
    When I press "Continue"
    Then I should see "Following field value must be select when create new users:"
    When I select "Student" from "user[puavoEduPersonAffiliation]"
    And I press "Continue"
    Then I should see the following users:
      | Ben | Mabey | ben.mabey | Class 4 | Student |
    When I press "Create users"
    Then I should see "Users (1) was successfully created."
    And I should see "You can print users list to paper, download pdf-file."

  Scenario: User mass import when user type is not defined and select empty value
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    Ben Karl	Mabey	Class 4
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Following field value must be select when create new users:"
    And I press "Continue"
    # Then I should see "User type is invalid"
    #When I fill in "users_import_invalid_list_3_0" with "Student"
    #And I fill in "users_import_invalid_list_3_1" with "Student"
    #And I press "Revalidate"
    #Then I should see "Username has already been taken"
    #When I fill in "users_import_invalid_list_0_0" with "Ben Karl"
    #And I fill in "users_import_invalid_list_4_0" with "benk.mabey"
    #And I press "Revalidate"
#    Then I should see the following users:
#      | Ben      | Mabey | Class 4 | Student | ben.mabey  |
#      | Ben Karl | Mabey | Class 4 | Student | benk.mabey |
#    When I press "Create users"
#    Then I should see "Users (2) was successfully created."
#    And I should see "You can print users list to paper, download pdf-file."
#    When I follow the PDF link "download pdf-file."
#    Then I should see "Name: Ben Mabey"
#    And I should see "Username: ben.mabey"
#    And I should see "Password"
#    And I should see "Name: Ben Karl Mabey"
#    And I should see "Username: benk.mabey"

  Scenario: User mass import without given name or surname
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select correct name of column for each data"
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
    Then I should see "Select correct name of column for each data"
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
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should not see "Role is invalid"
    And I should not see "Roles can't be blank"
    And I should see the following users:
      | Ben | Mabey | ben.mabey | cLaSs 4 | Student |

# Scenario: User mass import with invalid information
#    Given I send to the following user mass import data
#    """
#    Ben	Mabey	Class 5	Some
#    """
#    Then I should see "Select correct name of column for each data"
#    When I select "Given name" from "users_import_columns[0]"
#    And I select "Surname" from "users_import_columns[1]"
#    And I select "Role" from "users_import_columns[2]"
#    And I select "User type" from "users_import_columns[3]"
#    And I press "Validates users"
#    Then I should see "The following new users of the data are not valid. Please repair the information and select revalidate button."
#    And I should see "Role is invalid"
#    And I should not see "Roles can't be blank"
#    And I should see "User type is invalid"
#    And id the "users_import_invalid_list_2_0" field should not contain "#<ActiveLdap"
#    When I fill in "users_import_invalid_list_2_0" with "Class 4"
#    And I fill in "users_import_invalid_list_3_0" with "Student"
#    And I press "Revalidate"
#    And I should see the following users:
#      | Ben | Mabey | ben.mabey | Class 4 |
#    And I should not see "Roles can't be blank"
#    And I should not see "User type is invalid"
 
#  Scenario: Data does not lost with validation error case on user mass import
#    Given I send to the following user mass import data
#    """
#    Ben	Mabey	Class 4	Student
#    """
#    Then I should see "Select correct name of column for each data"
#    When I select "Given name" from "users_import_columns[0]"
#    And I select "Surname" from "users_import_columns[1]"
#    And I select "Given name" from "users_import_columns[2]"
#    And I select "User type" from "users_import_columns[3]"
#    And I fill in "users_import_raw_list_1_0" with "Wilk"
#    And I press "Validates users"
#    Then I should see "Duplicate column name"
#    And id the "users_import_raw_list_1_0" field should not contain "Mabey"
#    And id the "users_import_raw_list_1_0" field should contain "Wilk"
#    When I select "Given name" from "users_import_columns[0]"
#    And I select "Surname" from "users_import_columns[1]"
#    And I select "Role" from "users_import_columns[2]"
#    And I press "Validates users"
#    Then I should see the following users:
#      | Ben | Wilk | ben.wilk | Class 4 | Student |

  Scenario: Column selection does not lost with validation error case on user mass import
    Given I send to the following user mass import data
    """
    Ben	Mabey	Class 4
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Given name" from "users_import_columns[2]"
    And I press "Validates users"
    Then I should see "Duplicate column name"
#    And "Surname" should be selected for "users_import_columns_1"

  Scenario: User mass import when username already exists
    Given the following users:
      | givenName | sn    | uid       | password | role_name | puavoEduPersonAffiliation |
      | Ben       | Mabey | ben.mabey | secret   | Class 4   | Student                   |
    And I send to the following user mass import data
    """
    Ben	Mabey	Class 4	Student
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Role" from "users_import_columns[2]"
    And I select "User type" from "users_import_columns[3]"
    And I press "Validates users"
    Then I should see "Username has already been taken"

  Scenario: User mass import with duplicate username
    Given I send to the following user mass import data
    """
    Ken	Jones	ken.jones	Class 4	Student
    Ben	Mabey	ben.mabey	Class 4	Student
    Ben	Mabey	ben.mabey	Class 4	Student
    """
    Then I should see "Select correct name of column for each data"
    When I select "Given name" from "users_import_columns[0]"
    And I select "Surname" from "users_import_columns[1]"
    And I select "Username" from "users_import_columns[2]"
    And I select "Role" from "users_import_columns[3]"
    And I select "User type" from "users_import_columns[4]"
    And I press "Validates users"
    Then I should see "Username has already been taken"
    #When I fill in "users_import_invalid_list_2_0" with "ken.jones"
    #And I press "Revalidate"
    #Then I should see "Username has already been taken"
    #When I fill in "users_import_invalid_list_2_0" with "benj.mabey"
    #And I press "Revalidate"
    #Then I should see the following users:
    # | Ken | Jones | ken.jones  | Class 4 |
    # | Ben | Mabey | ben.mabey  | Class 4 |
    # | Ben | Mabey | benj.mabey | Class 4 |

#  Scenario: Skip duplicate username
#    Given I send to the following user mass import data
#    """
#    Ken	Jones	ken.jones	Class 4	Student
#    Ben	Mabey	ben.mabey	Class 4	Student
#    Ben	Mabey	ben.mabey	Class 4	Student
#    Ben	Mabey	ben.mabey	Class 4	Student
#    """
#    Then I should see "Select correct name of column for each data"
#    When I select "Given name" from "users_import_columns[0]"
#    And I select "Surname" from "users_import_columns[1]"
#    And I select "Username" from "users_import_columns[2]"
#    And I select "Role" from "users_import_columns[3]"
#    And I select "User type" from "users_import_columns[4]"
#    And I press "Validates users"
#    Then I should see "Username has already been taken"
#    When I check field by id "users_import_invalid_list_5_0"
#    When I check field by id "users_import_invalid_list_5_1"
#    And I press "Revalidate"
#    Then I should see the following users:
#    | Ken | Jones | ken.jones  | Class 4 |
#    | Ben | Mabey | ben.mabey  | Class 4 |
