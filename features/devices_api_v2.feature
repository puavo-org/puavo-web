Feature: Use device REST api version 2


  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following devices:
    | puavoHostname | macAddress        | puavoDeviceType |
    | testlaptop01  | bc:5f:f4:56:59:71 | laptop          |

  Scenario: Get device information in JSON
    When I find device by hostname "testlaptop01"
    Then I should see JSON '{"hostname": "testlaptop01", "mac_address": "bc:5f:f4:56:59:71"}'
