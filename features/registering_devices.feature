Feature: Devices registration

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation

  @start_test_server
  Scenario: Register new fatclient
    Given process activity is logged to "greenletters.log"
    Given a process "puavo-register" from command "fakeroot --lib /usr/lib/x86_64-linux-gnu/libfakeroot/libfakeroot-sysv.so /usr/sbin/puavo-register --puavoserver http://127.0.0.1:37634 --nocolor --force"
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
    Change (a)ll / (d)evice type / (s)chool / (h)ostname / (p)rimary user
      or register to Puavo with the above information? (y)es
    """
    When I enter "a" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Device type selection:
    1. Boot server
    2. Digital signage
    3. Fatclient
    4. Laptop
    5. LTSP server
    6. Netstand
    7. Other
    8. Printer
    9. Projector
    10. Switch (network)
    11. Thinclient
    12. Webcam
    13. Wireless access point
    14. Workstation
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
    When I enter "fake serial number" into process "puavo-register"
    When I enter "fake manufacturer" into process "puavo-register"
    When I enter "fake model" into process "puavo-register"
    When I enter "cucumber" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    HOST INFORMATION:
    Device type:            Thinclient
    School:                 Example school 1
    Hostname:               test-thin-01
    MAC address(es):        52:54:00:aa:aa:aa
    Serial number:          fake serial number
    Device manufacturer:    fake manufacturer
    Device model:           fake model
    Device primary user:    cucumber

    Change (a)ll / (d)evice type / (s)chool / (h)ostname / (p)rimary user
      or register to Puavo with the above information? (y)es
    """
    When I enter "y" into process "puavo-register"
    Then I should see the following output from process "puavo-register":
    """
    Sending host information to puavo server...
    *** OK: This machine is now successfully registered.
    """
