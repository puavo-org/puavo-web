Feature: Manage multiple schools
  In order to allow others to using all services
  As administrator
  I want to manage the set of users

  Background:
    Given the following schools:
    | displayName | cn      |
    | School 2    | school2 |
    | School 3    | school3 |

    Given a new school and group with names "School 1", "Class 4" on the "example" organisation

    And the following users:
      | givenName | sn     | uid    | password | school_admin | puavoEduPersonAffiliation |
      | Donald    | Duck   | donald | 313      | false        | teacher                   |
      | Admin     | Admin  | admin  | admin    | true         | admin                     |

    And I am logged in as "cucumber" with password "cucumber"

  Scenario: Add the user to another school
    Given I am on the show user page with "donald"
    And I follow "Change schools..."
    Then I should see:
      """
      Change the schools of user "Donald Duck"
      """
    And I should see "School 2" within "#available-school2"
    When I follow "Add to this school" within "#available-school2"
    Then I should see:
      """
      User added to school "School 2"
      """
    And I should see "(primary school)" within "#current-school1"
    And I should not see "(primary school)" within "#current-school2"
    Then I am on the show user page with "donald"
    And I should see "School 1 (primary school)" within "#schoolList"
    And I should see "School 2" within "#schoolList"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school

  Scenario: Remove the user from a school
    Given I am on the show user page with "donald"
    And I follow "Change schools..."
    Then I follow "Add to this school" within "#available-school2"
    Then I am on the show user page with "donald"
    And I should see "School 1 (primary school)" within "#schoolList"
    And I should see "School 2" within "#schoolList"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school
    And I follow "Change schools..."
    When I follow "Remove from this school" within "#current-school2"
    Then I should see:
      """
      User removed from school "School 2"
      """
    Then I am on the show user page with "donald"
    And I should not see "School 1 (primary school)"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should not include "donald" on the "School 2" school
    And the member should not include "donald" on the "School 2" school

  Scenario: Add and remove multiple schools
    Given I am on the show user page with "donald"
    # Add
    And I follow "Change schools..."
    Then I should see:
      """
      Change the schools of user "Donald Duck"
      """
    And I should see "School 2" within "#available-school2"
    When I follow "Add to this school" within "#available-school2"
    Then I should see:
      """
      User added to school "School 2"
      """
    When I follow "Add to this school" within "#available-school3"
    Then I should see:
      """
      User added to school "School 3"
      """
    And I should see "(primary school)" within "#current-school1"
    And I should not see "(primary school)" within "#current-school2"
    And I should not see "(primary school)" within "#current-school3"
    Then I am on the show user page with "donald"
    And I should see "School 1 (primary school)" within "#schoolList"
    And I should see "School 2" within "#schoolList"
    And I should see "School 3" within "#schoolList"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school
    And the memberUid should include "donald" on the "School 3" school
    And the member should include "donald" on the "School 3" school
    # Remove
    Then I follow "Change schools..."
    And I follow "Remove from this school" within "#current-school2"
    And I follow "Remove from this school" within "#current-school3"
    And I should see "(primary school)" within "#current-school1"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should not include "donald" on the "School 2" school
    And the member should not include "donald" on the "School 2" school
    And the memberUid should not include "donald" on the "School 3" school
    And the member should not include "donald" on the "School 3" school

  Scenario: Change (swap) the primary school
    # Setup
    Given I am on the show user page with "donald"
    And I follow "Change schools..."
    And I should see "School 2" within "#available-school2"
    When I follow "Add to this school" within "#available-school2"
    Then I should see "(primary school)" within "#current-school1"
    And I should not see "(primary school)" within "#current-school2"
    # Change
    When I follow "Set as the primary school" within "#current-school2"
    Then I should see:
      """
      Primary school set to "School 2"
      """
    And I should see "(primary school)" within "#current-school2"
    And I should not see "(primary school)" within "#current-school1"
    Then I am on the show user page with "donald"
    And I should see "School 2 (primary school)" within "#schoolList"
    And I should see "School 1" within "#schoolList"
    # Throw in a third school just for fun, but do it differently
    Then I follow "Change schools..."
    And I follow "Add and set as the primary school" within "#available-school3"
    Then I should see "(primary school)" within "#current-school3"
    And I should not see "(primary school)" within "#current-school2"
    And I should not see "(primary school)" within "#current-school1"
    Then I am on the show user page with "donald"
    And I should see "School 3 (primary school)" within "#schoolList"
    And I should see "School 2" within "#schoolList"
    And I should see "School 1" within "#schoolList"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school
    And the memberUid should include "donald" on the "School 3" school
    And the member should include "donald" on the "School 3" school
    # Remove the first school
    Then I follow "Change schools..."
    And I follow "Remove from this school" within "#current-school1"
    Then I should see "(primary school)" within "#current-school3"
    And I should not see "(primary school)" within "#current-school2"
    Then I am on the show user page with "donald"
    And I should see "School 3 (primary school)" within "#schoolList"
    And I should see "School 2" within "#schoolList"
    And I should not see "School 1" within "#content"
    And the memberUid should not include "donald" on the "School 1" school
    And the member should not include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school
    And the memberUid should include "donald" on the "School 3" school
    And the member should include "donald" on the "School 3" school
    # Remove the second school
    Then I follow "Change schools..."
    And I follow "Remove from this school" within "#current-school2"
    Then I should see "(primary school)" within "#current-school3"
    And I should see "Available schools (3)"
    Then I am on the show user page with "donald"
    And I should not see "School 1" within "#content"
    And I should not see "School 3" within "#content"
    And the memberUid should not include "donald" on the "School 1" school
    And the member should not include "donald" on the "School 1" school
    And the memberUid should not include "donald" on the "School 2" school
    And the member should not include "donald" on the "School 2" school
    And the memberUid should include "donald" on the "School 3" school
    And the member should include "donald" on the "School 3" school

  Scenario: Change the primary school directly
    Given I am on the show user page with "donald"
    # Change
    And I follow "Change schools..."
    When I follow "Add and set as the primary school" within "#available-school2"
    Then I should see:
      """
      User moved to the new primary school "School 2"
      """
    And I should see "(primary school)" within "#current-school2"
    And I should not see "(primary school)" within "#current-school1"
    And the memberUid should include "donald" on the "School 1" school
    And the member should include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school
    Then I am on the show user page with "donald"
    And I should see "School 2 (primary school)" within "#schoolList"
    And I should see "School 1" within "#schoolList"
    And I should not see "School 3" within "#content"
    # Ensure the primary school cannot be removed directly
    Then I follow "Change schools..."
    And I should not see "Remove from this school" within "#current-school2"
    And I should see "Remove from this school" within "#current-school1"

  Scenario: Move user directly to another school
    Given I am on the change schools page with "donald"
    Then I should see "School 2" within "#available-school2"
    And I should see "Move to this school" within "#available-school2"
    When I follow "Move to this school" within "#available-school2"
    Then I should see:
    """
    User moved to school "School 2"
    """
    And the memberUid should not include "donald" on the "School 1" school
    And the member should not include "donald" on the "School 1" school
    And the memberUid should include "donald" on the "School 2" school
    And the member should include "donald" on the "School 2" school

  Scenario: A user can be moved to another school directly only if they're in only one school
    Given I am on the change schools page with "donald"
    Then I should see "School 2" within "#available-school2"
    And I should see "Move to this school" within "#available-school2"
    And I should see "Move to this school" within "#available-school3"
    When I follow "Add to this school" within "#available-school2"
    Then I should not see "Move to this school" within "#available-school3"

  Scenario: Can see the user's admin status on the change schools page
    Given I am on the show user page with "admin"
    Then I should see:
      """
      This user is an administrator of the school "School 1"
      """
    Then I follow "Change schools..."
    And I should see "School admin" within "#current-school1"

  Scenario: When an admin user is removed from a school, they lose their admin status in that school
    # Check the admins page
    Given I am on the school page with "School 1"
    When I follow "Admins" within "div#tabs"
    And I should see "Admin Admin (admin) School 1" on the school admin list
    # Add another school (so that we can remove the current primary school)
    Given I am on the show user page with "admin"
    Then I follow "Change schools..."
    And I follow "Add and set as the primary school" within "#available-school2"
    Then I should see "School admin" within "#current-school1"
    And I should not see "School admin" within "#current-school2"
    # Remove the primary school
    When I follow "Remove from this school" within "#current-school1"
    Then I should not see "School admin" within "#current-school2"
    # Check
    Then I am on the show user page with "donald"
    And I should not see:
      """
      This user is an administrator of the school "School 1"
      """
    # Double-check the school admins page
    Given I am on the school page with "School 1"
    When I follow "Admins" within "div#tabs"
    And I should not see "Admin Admin (admin) School 1" on the school admin list

  Scenario: Admin rights are removed when user is moved directly to another school
    Given I am on the school page with "School 1"
    When I follow "Admins" within "div#tabs"
    And I should see "Admin Admin (admin) School 1" on the school admin list
    Then I am on the change schools page with "admin"
    And I follow "Move to this school" within "#available-school2"
    Then I should see:
    """
    User moved to school "School 2"
    """
    Then I am on the school page with "School 1"
    When I follow "Admins" within "div#tabs"
    Then I should not see "Admin Admin (admin) School 1" on the school admin list

  Scenario: Non-owners can't see or change other user's schools
    Given I am logged in as "admin" with password "admin"
    And I am on the show user page with "donald"
    Then I should not see "Change schools..."
    Given I am on the change schools page with "donald"
    Then I should see "You do not have enough rights to access that page."
