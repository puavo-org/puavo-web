Feature: Devices registration

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
  
  @start_test_server
  Scenario: Register new fatclient
    Given process activity is logged to "greenletters.log"
    Given a process "puavo-register" from command "fakeroot puavo-register --puavoserver http://127.0.0.1:37634 --nocolor"
    When I execute the process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
	-=< Puavo Devices Client >=-

    Puavo server name: [http://127.0.0.1:37634]
    """
    When I enter puavo server into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Username: []
    """
    When I enter "cucumber" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Password:
    """
    When I enter "cucumber" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Is this information correct? (y/n)
    """
    When I enter "n" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Device type selection:
    1. Thinclient
    2. Fatclient
    3. Laptop
    4. Workstation
    5. LTSP server
    6. Boot server
    7. Netstand
    8. Digital signage
    9. Printer
    10. Wireless access point
    11. Projector
    12. Webcam
    13. Switch (network)
    14. Other
    """
    When I enter "Thinclient" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    ===> selected [Thinclient]
    School selection:
    1. Administration
    2. Example school 1
    """
    When I enter "Example school 1" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    ===> selected [Example school 1]
    Hostname:
    """
    When I enter "test-thin-01" into process "puavo-register"
    When I enter "52:54:00:aa:aa:aa" into process "puavo-register"
    When I enter "" into process "puavo-register"
    When I enter "" into process "puavo-register"
    When I enter "" into process "puavo-register"
    When I enter "cucumber" into process "puavo-register"
    When I enter "" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    HOST INFORMATION:
    Device type:            Thinclient
    School:                 Example school 1
    Hostname:               test-thin-01
    MAC address(es):        52:54:00:aa:aa:aa
    Serial number:          
    Device manufacturer:    
    Device model:           
    Device primary user:    cucumber
    """
    When I enter "y" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Sending host information to puavo server...
    *** OK: This machine is now successfully registered.
    """
