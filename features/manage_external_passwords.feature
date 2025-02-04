Feature: Manage external passwords

  Testing that users in the "heroes" organisation can change passwords
  through the external login mechanism.  Users do not need to be
  setup in "external"-organisation, but as a side-effect of password
  changes they will be created there.  Users "lara.croft" (admin),
  "sarah.connor" (admin externally, teacher locally),
  "indiana.jones" (teacher), "luke.skywalker" (student), and "thomas.anderson"
  (student externally, admin locally) exist in the "heroes"-organisation,
  and "charlie.agent" (admin) and "david.agent" (student) do not.

  Background:
    Given a new school and group with names "School 1", "Class 1" on the "external" organisation
    And the following users:
    | givenName | sn     | uid           | password      | school_admin | puavoEduPersonAffiliation | mail                | school   |
    | Charlie   | Agent  | charlie.agent | charliesecret | true         | admin                     | charlie@example.com | School 1       |
    | David     | Agent  | david.agent   | davidsecret   | false        | student                   | david@example.com   | School 1       |
    | Edward    | Agent  | edward.agent  | edwardsecret  | false        | student                   | edward@example.com  | Administration |
    And I am on the password change page

  Scenario: Puavo-only admin can change password of another puavo-only user
    Given I am on the password change page
    When I fill in "login[uid]" with "charlie.agent"
    And I fill in "Password" with "charliesecret"
    And I fill in "user[uid]" with "david.agent"
    And I fill in "user[new_password]" with "newdavidsecret"
    And I fill in "Confirm new password" with "newdavidsecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "david.agent" and "davidsecret"
    And I should login with "david.agent" and "newdavidsecret"

  Scenario: External user fails to change own password with bad credentials
    Given I am on the own password change page
    When I fill in "Username" with "sarah.connor"
    And I fill in "Current password" with "wrong"
    And I fill in "user[new_password]" with "newsecret"
    And I fill in "Confirm new password" with "newsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (sarah.connor)"

  Scenario: External user changes their own password
    Given I am on the own password change page
    When I fill in "Username" with "sarah.connor"
    And I fill in "Current password" with "secret"
    And I fill in "user[new_password]" with "newsecret"
    And I fill in "Confirm new password" with "newsecret"
    And I wait 11 seconds
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "sarah.connor" and "secret"
    And I should login with "sarah.connor" and "newsecret"

  Scenario: External user changes their own password with another user form
    Given I am on the password change page
    When I fill in "login[uid]" with "sarah.connor"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "sarah.connor"
    And I fill in "user[new_password]" with "newsecret"
    And I fill in "Confirm new password" with "newsecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "sarah.connor" and "secret"
    And I should login with "sarah.connor" and "newsecret"

  Scenario: External user tries to change password without permissions
    Given I am on the password change page
    When I fill in "login[uid]" with "indiana.jones"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "lara.croft"
    And I fill in "user[new_password]" with "newlarasecret"
    And I fill in "Confirm new password" with "newlarasecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Can't change password to upstream service."

  Scenario: External user changes the password of external another user
    Given I am on the password change page
    When I fill in "login[uid]" with "sarah.connor"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "luke.skywalker"
    And I fill in "user[new_password]" with "newlukesecret"
    And I fill in "Confirm new password" with "newlukesecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "luke.skywalker" and "secret"
    And I should login with "luke.skywalker" and "newlukesecret"

# XXX test broken after commit
# https://github.com/puavo-org/puavo-os/commit/5bc77d1f164dc9f5de184b1583d9cb4112f058e1
# and that is probably okay.
# External logins sync only teacher and student roles, so "sarah.connor"
# must be a teacher for this to work (admin will not do).  But the ACL change
# denies teachers the permission to change student account passwords unless
# they are specifically given this permission.  But this permission should
# not be simply given to teachers in external logins either.  Should it be
# configurable?  But it should also be adjustable manually, as the admin roles
# are.  Because "Puavo-only" users are unusual, I do not think this test has
# much value and can be disabled for now.  But I am not removing this either,
# we may have to return to this later.
#
# Scenario: External admin changes password of Puavo-only user
#   Given I am on the password change page
#   When I fill in "login[uid]" with "sarah.connor"
#   And I fill in "Password" with "secret"
#   And I fill in "user[uid]" with "edward.agent"
#   And I fill in "user[new_password]" with "newedwardsecret"
#   And I fill in "Confirm new password" with "newedwardsecret"
#   And I press "Change password"
#   Then I should see "Password changed successfully!"
#   And I should not login with "edward.agent" and "edwardsecret"
#   And I should login with "edward.agent" and "newedwardsecret"

  Scenario: Puavo-only admin tries to change password of external user
    Given I am on the password change page
    When I fill in "login[uid]" with "charlie.agent"
    And I fill in "Password" with "charliesecret"
    And I fill in "user[uid]" with "luke.skywalker"
    And I fill in "user[new_password]" with "newlukesecret"
    And I fill in "Confirm new password" with "newlukesecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "User (luke.skywalker) does not exist"

  Scenario: External admin tries to change password of non-existing user
    Given I am on the password change page
    When I fill in "login[uid]" with "sarah.connor"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "notexisting"
    And I fill in "user[new_password]" with "newnotexistingsecret"
    And I fill in "Confirm new password" with "newnotexistingsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "User (notexisting) does not exist"

  Scenario: External user tries to change password of Puavo-only user
    Given I am on the password change page
    When I fill in "login[uid]" with "luke.skywalker"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "david.agent"
    And I fill in "user[new_password]" with "newdavidsecret"
    And I fill in "Confirm new password" with "newdavidsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "You cannot change other user's passwords."

  Scenario: Non-existing user tries to change password of external user
    Given I am on the password change page
    When I fill in "login[uid]" with "nonexisting"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "luke.skywalker"
    And I fill in "user[new_password]" with "newlukesecret"
    And I fill in "Confirm new password" with "newlukesecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (nonexisting)"

  Scenario: Puavo-only user tries to change password of external user
    Given I am on the password change page
    When I fill in "login[uid]" with "charlie.agent"
    And I fill in "Password" with "charliesecret"
    And I fill in "user[uid]" with "luke.skywalker"
    And I fill in "user[new_password]" with "newlukesecret"
    And I fill in "Confirm new password" with "newlukesecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "User (luke.skywalker) does not exist"

  Scenario: External admin tries to change password of Puavo-only admin
    Given I am on the password change page
    When I fill in "login[uid]" with "sarah.connor"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "charlie.agent"
    And I fill in "user[new_password]" with "newcharliesecret"
    And I fill in "Confirm new password" with "newcharliesecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Password change failed"

  Scenario: External admin changes pw for another admin (no perms in Puavo)

    External admin tries to change the password of another external admin,
    but with a twist that the admin does have the necessary permissions
    only in external service and not in Puavo.  This is a configuration
    error and thus this should not happen, but in case it does this
    test checks what should happen.  On the first password change the
    target user is created to Puavo, the password is not changed to Puavo
    directly, and thus it succeeds.  The second attempt however fails in
    such a way, that password is first changed to external service, and
    then direct changing to Puavo fails, but this does not matter much
    because the password has been changed to external service anyway and
    it should sync on the next login.  This behaviour is rather strange,
    but as long as the password permissions are more lax on the Puavo-side
    (which should always be the case or at least external logins should be
    configured in such a way), this situation should never arise.

    Given I am on the password change page
    When I fill in "login[uid]" with "lara.croft"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "sarah.connor"
    And I fill in "user[new_password]" with "newsarahsecret"
    And I fill in "Confirm new password" with "newsarahsecret"
    And I press "Change password"
    Then I should see "Password changed successfully!"
    And I should not login with "sarah.connor" and "secret"
    And I should login with "sarah.connor" and "newsarahsecret"
    Given I am on the password change page
    When I fill in "login[uid]" with "lara.croft"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "sarah.connor"
    And I fill in "user[new_password]" with "nextsarahsecret"
    And I fill in "Confirm new password" with "nextsarahsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should not login with "sarah.connor" and "nextsarahsecret"
    And I should login with "sarah.connor" and "newsarahsecret"

  Scenario: External user tries to change pw for another user (with permissions in Puavo)
    Given I am on the password change page
    When I fill in "login[uid]" with "thomas.anderson"
    And I fill in "Password" with "secret"
    And I fill in "user[uid]" with "sarah.connor"
    And I fill in "user[new_password]" with "newsarahsecret"
    And I fill in "Confirm new password" with "newsarahsecret"
    And I press "Change password"
    Then I should not see "Password changed successfully!"
    And I should see "Invalid password or username (thomas.anderson)"
