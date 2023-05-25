Feature: Manage admin permissions
  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following users:
      | givenName | sn     | uid        | password | school_admin | puavoEduPersonAffiliation |
      | Test      | User   | testuser   | password | false        | testuser                  |
      | Test      | Admin  | testadmin  | password | true         | admin                     |
      | Test2     | Admin2 | testadmin2 | password | true         | admin                     |

  Scenario: Owners can edit admin permissions
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the show user page with "testadmin"
    Then I should see "Edit admin permissions..."
    When I follow "Edit admin permissions..."
    Then I should not see "You do not have enough rights to access that page"

  Scenario: Owners have all permissions by default
    Given I am logged in as "cucumber" with password "cucumber"
    When I am on the school users list page
    Then I should see "New user..."
    And I should see "Remove"
    And I should see "Import and update users"

  Scenario: Can't edit permissions of a non-admin user
    Given I am logged in as "cucumber" with password "cucumber"
    Then I am on the show user page with "testuser"
    Then I should not see "Edit admin permissions..."
    # Direct URL manipulation
    Then I am on the edit admin permissions page with "testuser"
    Then I should see "Cannot edit admin permissions, because the user is not an admin"

  Scenario: Admins can't edit their own permissions
    Given I am logged in as "testadmin" with password "password"
    # No "edit permissions" button
    And I am on the show user page with "testadmin"
    Then I should not see "Edit admin permissions..."
    # Try someone else's page
    And I am on the show user page with "testadmin2"
    Then I should not see "Edit admin permissions..."
    # Try to edit the page directly
    Given I am on the edit admin permissions page with "testadmin"
    Then I should see "You do not have enough rights to access that page."
    Given I am on the edit admin permissions page with "testadmin2"
    Then I should see "You do not have enough rights to access that page."

  Scenario: Admins have no permissions by default
    Given I am logged in as "testadmin" with password "password"
    When I am on the school users list page
    Then I should not see "New user..."
    And I should not see "Remove"
    And I should not see "Import and update users"

  Scenario: Permit new user creation
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the edit admin permissions page with "testadmin"
    When I check "create_users"
    And I press "Update"
    Then I should see "Permissions updated"
    Then I should see "Admin permissions can create users"
    Given I am logged in as "testadmin" with password "password"
    When I am on the show user page with "testadmin"
    Then I should see "Admin permissions can create users"
    When I am on the school users list page
    Then I should see "New user..."
    And I should not see "Remove"
    And I should not see "Import and update users"
    When I follow "New user..."
    Then I should not see "You do not have enough rights to access that page."

  Scenario: Permit user deletion
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the edit admin permissions page with "testadmin"
    When I check "delete_users"
    And I press "Update"
    Then I should see "Permissions updated"
    Then I should see "Admin permissions can delete users"
    Given I am logged in as "testadmin" with password "password"
    When I am on the show user page with "testadmin"
    Then I should see "Admin permissions can delete users"
    When I am on the school users list page
    Then I should not see "New user..."
    And I should see "Remove"
    And I should not see "Import and update users"

  Scenario: Permit users mass import tool
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the edit admin permissions page with "testadmin"
    When I check "import_users"
    And I press "Update"
    Then I should see "Permissions updated"
    Then I should see "Admin permissions user mass import tool"
    Given I am logged in as "testadmin" with password "password"
    When I am on the show user page with "testadmin"
    Then I should see "Admin permissions user mass import tool"
    When I am on the school users list page
    Then I should not see "New user..."
    And I should not see "Remove"
    And I should see "Import and update users"
    When I follow "Import and update users"
    Then I should see "User Mass Import and Update"
    # No user creation rights
    And I should see "You can't create new users, so the update method (see below) has been locked to updating existing users only."

  Scenario: Permit everything
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the edit admin permissions page with "testadmin"
    When I check "create_users"
    When I check "delete_users"
    When I check "import_users"
    And I press "Update"
    Then I should see "Permissions updated"
    Then I should see "Admin permissions can create users, can delete users, user mass import tool"
    Given I am logged in as "testadmin" with password "password"
    When I am on the show user page with "testadmin"
    Then I should see "Admin permissions can create users, can delete users, user mass import tool"
    When I am on the school users list page
    Then I should see "New user..."
    And I should see "Remove"
    And I should see "Import and update users"
    When I follow "New user..."
    Then I should not see "You do not have enough rights to access that page."
    When I follow "Import and update users"
    Then I should not see "You do not have enough rights to access that page."

  Scenario: Removing the admin role will reset all admin permissions
    # Add permissions
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the edit admin permissions page with "testadmin"
    When I check "create_users"
    When I check "delete_users"
    When I check "import_users"
    And I press "Update"
    Then I should see "Permissions updated"
    Then I should see "Admin permissions can create users, can delete users, user mass import tool"
    # Take them away
    Then I am on the edit user page with "testadmin"
    And I uncheck "puavoEduPersonAffiliation_admin"
    And I check "puavoEduPersonAffiliation_testuser"
    And I press "Update"
    # Verify
    Then I should not see "Edit admin permissions..."
    Then I should not see "Admin permissions can create users, can delete users, user mass import tool"
    # That was fun, let's do it again!
    Then I am on the edit user page with "testadmin"
    And I check "puavoEduPersonAffiliation_admin"
    And I uncheck "puavoEduPersonAffiliation_testuser"
    And I press "Update"
    Then I should see "Edit admin permissions..."
    Then I should not see "Admin permissions can create users, can delete users, user mass import tool"
