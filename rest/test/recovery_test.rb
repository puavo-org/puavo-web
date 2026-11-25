# Remote recovery: opening, device and key service calls

require 'jwt'
require 'minitest/mock'

require_relative 'helper'
require_relative 'oauth2_helpers'

module RecoveryTest
ORGANISATION_ID = 'example-organisation'
SERIAL_NUMBER = 'SERIAL-1234'
KEY_SERVICE_CLIENT = 'test_client_recovery_key_service'
KEY_SERVICE_SCOPE = PuavoRest::Recoveries::KEY_SERVICE_SCOPE
OTHER_SCOPE = 'puavo.read.organisation'
CLIENT_SECRET = 'keyservicesecret'
USER_PASSWORD = 'secret'
OTHER_HOST = 'anotherorg.puavo.net'
OTHER_ORGANISATION_ID = 'another-organisation'
RETURN_KEY = OpenSSL::PKey::RSA.new(3072)
ENCRYPTED_KEY = 'the recovery key, encrypted to the return key'
WRONG_CODE = '22222222'
DeviceRecovery = PuavoRest::DeviceRecovery

describe PuavoRest::Recoveries do
  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection
    DeviceRecovery.redis.keys('*').each do |key|
      DeviceRecovery.redis.del(key)
    end

    organisation = PuavoRest::Organisation.default_organisation_domain!
    organisation.device_recovery_public_key = {
      'organisation_id' => ORGANISATION_ID,
    }
    organisation.save!

    test_organisation = Puavo::Organisation.find('example')
    @owner_name = test_organisation.owner
    @owner_password = test_organisation.owner_pw
    @school = School.create(cn: 'gryffindor', displayName: 'Gryffindor')
    create_device(puavoHostname: 'laptop1', serialNumber: SERIAL_NUMBER,
                  puavoSchool: @school.dn)

    @teacher = PuavoRest::User.new(first_name: 'Bob', last_name: 'Brown',
                                   username: 'bob', password: USER_PASSWORD,
                                   roles: ['teacher'],
                                   school_dns: [@school.dn.to_s])
    @teacher.save!

    @bundle = '{"serial_number":"SERIAL-1234"}'
    @return_key = RETURN_KEY.public_key.to_der

    oauth2_client_db do |db|
      delete_test_client_data(db)
      create_token_client(db, KEY_SERVICE_CLIENT,
                          [KEY_SERVICE_SCOPE, OTHER_SCOPE],
                          endpoints: ['/v3/recovery/queue',
                                      '/v3/recovery/requests/:id/result'])
      create_client_authentication(db, KEY_SERVICE_CLIENT,
                                   'client_secret_basic',
                                   params: { password: CLIENT_SECRET })
    end
  end

  after(:each) do
    oauth2_client_db { |db| delete_test_client_data(db) }
  end

  def body_of(response)
    JSON.parse(response.body)
  end

  def error_code_of(response)
    body_of(response)['error']['code']
  end

  def send_json(method, path, body)
    send(method, path, body.to_json, 'CONTENT_TYPE' => 'application/json')
  end

  def act_as_owner
    header 'Authorization', nil
    basic_authorize @owner_name, @owner_password
  end

  def act_as_user(username)
    header 'Authorization', nil
    basic_authorize username, USER_PASSWORD
  end

  def act_as_device
    header 'Authorization', nil
  end

  def act_as_key_service(scope = KEY_SERVICE_SCOPE)
    header 'Authorization', nil
    basic_authorize KEY_SERVICE_CLIENT, CLIENT_SECRET
    token_response = post('/oidc/token', 'grant_type' => 'client_credentials',
                                         'scope' => scope)
    assert_200(token_response)
    access_token = body_of(token_response)['access_token']
    header 'Authorization', "Bearer #{ access_token }"
  end

  # Adds a laptop whose hostname and serial number end in the number, for
  # example "laptop5" and "SERIAL-5".
  def add_laptop(number)
    create_device(puavoHostname: "laptop#{ number }",
                  serialNumber: "SERIAL-#{ number }",
                  puavoSchool: @school.dn,
                  macAddress: format('bc:5f:f4:56:5a:%02x', number))
  end

  def request_opening(hostname)
    act_as_owner
    post "/v3/devices/#{ hostname }/recovery"
  end

  # @return [Hash] what the owner gets at the opening
  def open_recovery(hostname = 'laptop1')
    open_response = request_opening(hostname)
    assert_equal 200, open_response.status, open_response.body
    body_of(open_response)
  end

  # Opens the recoveries a second apart, so their queue order is known.
  # @return [Array<Hash>] what the owner gets at each opening
  def open_in_order(hostnames)
    start = Time.now
    hostnames.each_with_index.map do |hostname, index|
      Timecop.freeze(start + index) do
        open_recovery(hostname)
      end
    end
  end

  def show_recovery
    act_as_owner
    get '/v3/devices/laptop1/recovery'
  end

  def close_recovery
    act_as_owner
    delete '/v3/devices/laptop1/recovery'
  end

  def join(code, fields = {})
    act_as_device
    send_json(:post, '/v3/recovery/requests', {
      'organisation_id' => ORGANISATION_ID,
      'serial_number' => SERIAL_NUMBER,
      'code' => code,
      'bundle' => Base64.strict_encode64(@bundle),
      'return_public_key' => Base64.strict_encode64(@return_key),
    }.merge(fields))
  end

  # Opens a recovery and joins it.
  # @return [Hash] what the device gets at the join
  def queue_request(hostname = 'laptop1', serial_number = SERIAL_NUMBER)
    opened = open_recovery(hostname)
    join_response = join(opened['code'], 'serial_number' => serial_number)
    assert_equal 201, join_response.status, join_response.body
    body_of(join_response)
  end

  def poll(id)
    act_as_device
    get "/v3/recovery/requests/#{ id }"
  end

  # The device's delete of its request. While the request waits or after it
  # failed, the delete is a cancel. After a result, it ends the recovery.
  def delete_request(id)
    act_as_device
    delete "/v3/recovery/requests/#{ id }"
  end

  def fetch_queue
    act_as_key_service
    get '/v3/recovery/queue'
  end

  # @return [Array<String>] the ids the key service fetches
  def queued_ids
    queue_response = fetch_queue
    assert_200(queue_response)
    body_of(queue_response)['requests'].map { |entry| entry['id'] }
  end

  # Makes three calls with the credentials set before: who the caller is,
  # then the two key service calls.
  # @return [Array<Integer>] the statuses of the three calls
  def statuses_of_calls(id)
    whoami_response = get('/v3/whoami')
    queue_response = get('/v3/recovery/queue')
    result_response = send_json(
      :put, "/v3/recovery/requests/#{ id }/result",
      'result' => Base64.strict_encode64(ENCRYPTED_KEY))
    [whoami_response.status, queue_response.status, result_response.status]
  end

  def store_result(id)
    act_as_key_service
    send_json(:put, "/v3/recovery/requests/#{ id }/result",
              'result' => Base64.strict_encode64(ENCRYPTED_KEY))
  end

  def store_error(id, error)
    act_as_key_service
    send_json(:put, "/v3/recovery/requests/#{ id }/result", 'error' => error)
  end

  def own_domain
    PuavoRest::Organisation.default_organisation_domain!.domain
  end

  def own_record_key
    DeviceRecovery.record_key(own_domain, SERIAL_NUMBER)
  end

  # Adds a laptop with our serial number to the other test organisation,
  # and gives that organisation a recovery key.
  # @return [Array<String>] the DN and password of its owner
  def add_other_organisation_laptop
    owner_dn, owner_password = Puavo::Test.setup_test_connection('anotherorg')

    # The cleanup before each test covers only our organisation.
    Device.find(:all, attribute: 'puavoHostname', value: 'laptop1')
          .each(&:destroy)
    School.find(:all, attribute: 'cn', value: 'slytherin').each(&:destroy)

    school = School.create(cn: 'slytherin', displayName: 'Slytherin')
    create_device(puavoHostname: 'laptop1', serialNumber: SERIAL_NUMBER,
                  puavoSchool: school.dn)
    recovery_key = { 'organisation_id' => OTHER_ORGANISATION_ID }
    organisation = LdapOrganisation.current
    organisation.puavoDeviceRecoveryPublicKey = recovery_key.to_json
    organisation.save!

    Puavo::Test.setup_test_connection('example')
    setup_ldap_admin_connection
    [owner_dn, owner_password]
  end

  # Opens and joins a recovery in the other test organisation through its
  # own host, for a laptop with the same serial number as ours.
  # @return [Hash] the request id and the code
  def join_other_organisation
    owner_dn, owner_password = add_other_organisation_laptop()
    header 'Host', OTHER_HOST
    basic_authorize owner_dn, owner_password
    open_response = post('/v3/devices/laptop1/recovery')
    assert_equal 200, open_response.status, open_response.body
    other_recovery = body_of(open_response)

    join_response = join(other_recovery['code'],
                         'organisation_id' => OTHER_ORGANISATION_ID)
    assert_equal 201, join_response.status, join_response.body
    other_request = body_of(join_response)
    { 'id' => other_request['id'], 'code' => other_recovery['code'] }
  ensure
    header 'Host', nil
  end

  it 'takes a recovery from opening to result and acknowledgement' do
    opened = open_recovery()
    assert_equal 'open', opened['state']
    assert_equal SERIAL_NUMBER, opened['serial_number']
    assert_match(/\A[23456789A-HJ-NP-X]{8}\z/, opened['code'])

    show_response = show_recovery()
    assert_200(show_response)
    shown_recovery = body_of(show_response)
    assert_equal opened['code'], shown_recovery['code']
    assert_equal @owner_name, shown_recovery['opened_by']
    assert_equal 0, shown_recovery['wrong_codes']

    # Both times are stored at the opening, so the test speed plays no part.
    lifetime = Time.iso8601(shown_recovery['expires_at']) -
               Time.iso8601(shown_recovery['created_at'])
    assert_equal DeviceRecovery::LIFETIME, lifetime

    # People type the code in any case, with a space between its halves.
    typed_code = "#{ opened['code'][0, 4] } #{ opened['code'][4, 4] }"
    join_response = join(typed_code.downcase)
    assert_equal 201, join_response.status, join_response.body
    joined = body_of(join_response)
    id_length = joined['id'].size
    assert_equal 'queued', joined['state']
    assert_equal 43, id_length

    # First in the queue, so the device polls at the shortest interval.
    poll_response = poll(joined['id'])
    polled_request = body_of(poll_response)
    assert_equal 1, polled_request['queue_position']
    assert_equal DeviceRecovery::MIN_POLL_SECONDS,
                 polled_request['poll_seconds']

    approval = polled_request['approval']
    approval_key = OpenSSL::PKey.read(
      PuavoRest::RecoveryApproval::PRIVATE_KEY.public_to_pem)
    claims, jwt_header = JWT.decode(approval, approval_key, true,
                                    algorithm: 'ES256', aud: 'puavo-kps',
                                    verify_aud: true)
    digest = DeviceRecovery.digest(@bundle, @return_key)
    expires_at = Time.iso8601(opened['expires_at']).to_i
    assert_equal 'recovery-approval-test', jwt_header['kid']
    assert_equal joined['id'], claims['jti']
    assert_equal digest, claims['digest']
    assert_equal SERIAL_NUMBER, claims['serial_number']
    assert_equal ORGANISATION_ID, claims['organisation_id']
    assert_equal @owner_name, claims['approver']
    assert_equal expires_at, claims['exp']

    # The code shows only while open, so nobody reads it off a queued
    # recovery and joins with it.
    queued_show_response = show_recovery()
    queued_recovery = body_of(queued_show_response)
    assert_equal 'queued', queued_recovery['state']
    assert_equal 1, queued_recovery['queue_position']
    assert_nil queued_recovery['code']

    queue_response = fetch_queue()
    assert_200(queue_response)
    fetched_requests = body_of(queue_response)['requests']
    fetched_ids = fetched_requests.map { |entry| entry['id'] }
    fetched_request = fetched_requests.first
    encoded_bundle = Base64.strict_encode64(@bundle)
    assert_equal [joined['id']], fetched_ids
    assert_equal approval, fetched_request['approval']
    assert_equal encoded_bundle, fetched_request['bundle']

    result_response = store_result(joined['id'])
    assert_200(result_response)
    stored_answer = body_of(result_response)
    assert_equal 'done', stored_answer['state']

    done_poll_response = poll(joined['id'])
    encoded_result = Base64.strict_encode64(ENCRYPTED_KEY)
    done_request = body_of(done_poll_response)
    assert_equal encoded_result, done_request['result']

    # After a result the device's delete is its acknowledgement: the
    # recovery ends.
    acknowledge_response = delete_request(joined['id'])
    assert_200(acknowledge_response)
    ended_poll_response = poll(joined['id'])
    assert_equal 404, ended_poll_response.status
    ended_show_response = show_recovery()
    assert_equal 404, ended_show_response.status
  end

  it 'answers a join of another organisation as no recovery' do
    opened = open_recovery()
    join_response = join(opened['code'], 'organisation_id' => 'other')
    join_error = error_code_of(join_response)
    assert_equal 404, join_response.status
    assert_equal 'RecoveryRequestNotFound', join_error

    # The code was not tried, so it is not counted.
    show_response = show_recovery()
    shown_recovery = body_of(show_response)
    assert_equal 'open', shown_recovery['state']
    assert_equal 0, shown_recovery['wrong_codes']
  end

  it 'reads no LDAP for a join that matches no record' do
    read_organisation = proc { raise 'LDAP read' }
    join_response = nil
    PuavoRest::Organisation.stub(:by_dn, read_organisation) do
      join_response = join(WRONG_CODE)
    end

    join_error = error_code_of(join_response)
    assert_equal 404, join_response.status
    assert_equal 'RecoveryRequestNotFound', join_error
  end

  it 'answers no recovery and a wrong code alike' do
    unknown_join_response = join(WRONG_CODE)
    unknown_join_error = error_code_of(unknown_join_response)
    stored_keys = DeviceRecovery.redis.keys('*')
    assert_equal 404, unknown_join_response.status
    assert_equal 'RecoveryRequestNotFound', unknown_join_error
    assert_equal [], stored_keys

    open_recovery()
    opened_show_response = show_recovery()
    opened_recovery = body_of(opened_show_response)
    assert_equal 0, opened_recovery['wrong_codes']

    wrong_join_response = join(WRONG_CODE)
    wrong_join_error = error_code_of(wrong_join_response)
    assert_equal 404, wrong_join_response.status
    assert_equal 'RecoveryRequestNotFound', wrong_join_error

    show_response = show_recovery()
    shown_recovery = body_of(show_response)
    assert_equal 1, shown_recovery['wrong_codes']
  end

  it 'closes the recovery at the last wrong code allowed' do
    opened = open_recovery()
    (DeviceRecovery::MAX_WRONG_CODES - 1).times do
      join_response = join(WRONG_CODE)
      assert_equal 404, join_response.status
    end

    # One wrong code left, and the recovery is still there.
    before_last_response = show_recovery()
    recovery_before_last = body_of(before_last_response)
    wrong_codes_so_far = DeviceRecovery::MAX_WRONG_CODES - 1
    assert_equal 'open', recovery_before_last['state']
    assert_equal wrong_codes_so_far, recovery_before_last['wrong_codes']

    last_join_response = join(WRONG_CODE)
    assert_equal 404, last_join_response.status

    show_response = show_recovery()
    assert_equal 404, show_response.status

    # The right code finds nothing either: the recovery is gone.
    right_join_response = join(opened['code'])
    assert_equal 404, right_join_response.status
  end

  it 'closes a done recovery at the last wrong code allowed' do
    joined = queue_request()
    store_result(joined['id'])

    (DeviceRecovery::MAX_WRONG_CODES - 1).times do
      join_response = join(WRONG_CODE)
      assert_equal 404, join_response.status
    end

    # One wrong code left, and the result is still there.
    before_last_response = poll(joined['id'])
    request_before_last = body_of(before_last_response)
    assert_equal 'done', request_before_last['state']

    last_join_response = join(WRONG_CODE)
    assert_equal 404, last_join_response.status

    poll_response = poll(joined['id'])
    assert_equal 404, poll_response.status
    show_response = show_recovery()
    assert_equal 404, show_response.status
  end

  it 'ignores a join field it does not know and keeps it nowhere' do
    opened = open_recovery()
    join_response = join(opened['code'], 'rubber_duck' => 'quack')
    assert_equal 201, join_response.status, join_response.body
    joined = body_of(join_response)

    poll_response = poll(joined['id'])
    show_response = show_recovery()
    queue_response = fetch_queue()
    stored_record = DeviceRecovery.redis.get(own_record_key)

    texts_by_place = {
      'join answer' => join_response.body,
      'device poll' => poll_response.body,
      'owner view' => show_response.body,
      'key service queue' => queue_response.body,
      'stored record' => stored_record,
    }
    texts_by_place.each do |where, text|
      refute_includes text, 'rubber_duck', where
      refute_includes text, 'quack', where
    end
  end

  it 'hides the recoveries of another organisation' do
    other_request = join_other_organisation()

    poll_response = poll(other_request['id'])
    assert_equal 404, poll_response.status
    delete_response = delete_request(other_request['id'])
    assert_equal 404, delete_response.status

    # The serial number is the same, but no recovery of this organisation
    # has it.
    join_response = join(other_request['code'])
    assert_equal 404, join_response.status
    show_response = show_recovery()
    assert_equal 404, show_response.status
  end

  it 'lets only owners open, see and close recoveries' do
    # Bob may not open a recovery, because he is a teacher and not an owner.
    act_as_user('bob')
    bob_open_response = post('/v3/devices/laptop1/recovery')
    assert_equal 403, bob_open_response.status

    # Nor see or close the one the owner opened.
    open_recovery()
    act_as_user('bob')
    bob_show_response = get('/v3/devices/laptop1/recovery')
    assert_equal 403, bob_show_response.status
    bob_close_response = delete('/v3/devices/laptop1/recovery')
    assert_equal 403, bob_close_response.status
  end

  it 'refuses to open a recovery of a device without a serial number' do
    create_device(puavoHostname: 'laptop2', puavoSchool: @school.dn,
                  macAddress: 'bc:5f:f4:56:59:72')
    open_response = request_opening('laptop2')
    open_error = error_code_of(open_response)

    # A conflict: the call is right, but the device lacks what an opening
    # needs.
    assert_equal 409, open_response.status
    assert_equal 'DeviceWithoutSerialNumber', open_error
  end

  it 'opens, shows and closes the recovery of a boot server' do
    boot_server = Server.new
    boot_server.attributes = {
      puavoHostname: 'bootserver1', puavoDeviceType: 'bootserver',
      serialNumber: 'SERIAL-SERVER', puavoSchool: @school.dn,
      macAddress: 'bc:5f:f4:56:59:74',
    }
    boot_server.save!

    queued_request = queue_request('bootserver1', 'SERIAL-SERVER')
    act_as_owner
    show_response = get('/v3/devices/bootserver1/recovery')
    shown_recovery = body_of(show_response)
    close_response = delete('/v3/devices/bootserver1/recovery')
    after_close_response = get('/v3/devices/bootserver1/recovery')

    assert_equal 'queued', queued_request['state']
    assert_equal 200, show_response.status
    assert_equal 'SERIAL-SERVER', shown_recovery['serial_number']
    assert_equal 'queued', shown_recovery['state']
    assert_equal 200, close_response.status
    assert_equal 404, after_close_response.status
  end

  it 'refuses to open a recovery of a device type without recovery' do
    create_device(puavoHostname: 'fatclient1', puavoDeviceType: 'fatclient',
                  serialNumber: 'SERIAL-5678', puavoSchool: @school.dn,
                  macAddress: 'bc:5f:f4:56:59:73')
    open_response = request_opening('fatclient1')
    open_error = error_code_of(open_response)
    assert_equal 409, open_response.status
    assert_equal 'UnsupportedDeviceType', open_error
  end

  it 'ends the earlier recovery of the device at a new opening' do
    first_request = queue_request()
    second_recovery = open_recovery()
    assert_equal 'open', second_recovery['state']

    poll_response = poll(first_request['id'])
    queued_request_ids = queued_ids()
    assert_equal 404, poll_response.status
    assert_equal [], queued_request_ids
  end

  it 'closes a recovery at any state' do
    joined = queue_request()
    close_response = close_recovery()
    assert_200(close_response)

    poll_response = poll(joined['id'])
    queued_request_ids = queued_ids()
    assert_equal 404, poll_response.status
    assert_equal [], queued_request_ids

    show_response = show_recovery()
    assert_equal 404, show_response.status
    second_close_response = close_recovery()
    assert_equal 404, second_close_response.status
  end

  it 'opens the recovery again when the device cancels' do
    opened = open_recovery()
    first_join_response = join(opened['code'])
    first_request = body_of(first_join_response)

    cancel_response = delete_request(first_request['id'])
    assert_200(cancel_response)

    poll_response = poll(first_request['id'])
    show_response = show_recovery()
    queued_request_ids = queued_ids()
    shown_recovery = body_of(show_response)
    assert_equal 404, poll_response.status
    assert_equal 'open', shown_recovery['state']
    assert_equal [], queued_request_ids

    second_join_response = join(opened['code'])
    second_request = body_of(second_join_response)
    assert_equal 201, second_join_response.status
    refute_equal first_request['id'], second_request['id']
  end

  it 'opens the recovery again when the device deletes a failed request' do
    opened = open_recovery()
    join_response = join(opened['code'])
    request_to_fail = body_of(join_response)
    store_error(request_to_fail['id'], 'code' => 'UnwrapFailed',
                                       'message' => '')

    delete_response = delete_request(request_to_fail['id'])
    assert_200(delete_response)

    poll_response = poll(request_to_fail['id'])
    show_response = show_recovery()
    shown_recovery = body_of(show_response)
    assert_equal 404, poll_response.status
    assert_equal 'open', shown_recovery['state']

    rejoin_response = join(opened['code'])
    assert_equal 201, rejoin_response.status
  end

  it 'lets the first join win' do
    opened = open_recovery()
    first_join_response = join(opened['code'])
    first_request = body_of(first_join_response)

    # Another bundle, so somebody else with a copy of the code.
    other_bundle = Base64.strict_encode64('{"copy":true}')
    other_join_response = join(opened['code'], 'bundle' => other_bundle)
    other_join_error = error_code_of(other_join_response)
    assert_equal 409, other_join_response.status
    assert_equal 'CodeInUse', other_join_error

    poll_response = poll(first_request['id'])
    queued_request_ids = queued_ids()
    assert_200(poll_response)
    assert_equal [first_request['id']], queued_request_ids
  end

  it 'answers the same join sent again with its request' do
    opened = open_recovery()
    first_join_response = join(opened['code'])
    first_request = body_of(first_join_response)

    repeated_join_response = join(opened['code'])
    repeated_request = body_of(repeated_join_response)
    queued_request_ids = queued_ids()
    assert_200(repeated_join_response)
    assert_equal first_request['id'], repeated_request['id']
    assert_equal 'queued', repeated_request['state']
    assert_equal [first_request['id']], queued_request_ids
  end

  it 'replaces a failed request at the next join' do
    opened = open_recovery()
    first_join_response = join(opened['code'])
    request_to_fail = body_of(first_join_response)
    store_error(request_to_fail['id'], 'code' => 'UnwrapFailed',
                                       'message' => '')

    second_join_response = join(opened['code'])
    assert_equal 201, second_join_response.status
    second_request = body_of(second_join_response)

    poll_response = poll(request_to_fail['id'])
    queued_request_ids = queued_ids()
    assert_equal 404, poll_response.status
    assert_equal [second_request['id']], queued_request_ids
  end

  it 'refuses a join after a result but rejoining works after an error' do
    recovery_to_finish = open_recovery()
    finished_join_response = join(recovery_to_finish['code'])
    finished_id = body_of(finished_join_response)['id']
    store_result(finished_id)

    after_result_response = join(recovery_to_finish['code'])
    after_result_error = error_code_of(after_result_response)
    assert_equal 409, after_result_response.status
    assert_equal 'WrongState', after_result_error

    recovery_to_fail = open_recovery()
    failing_join_response = join(recovery_to_fail['code'])
    failing_id = body_of(failing_join_response)['id']
    error_response = store_error(failing_id,
                                 'code' => 'UnwrapFailed', 'message' => '')
    assert_200(error_response)

    after_error_response = join(recovery_to_fail['code'])
    assert_equal 201, after_error_response.status
  end

  it 'keeps the expiry of the opening in every state' do
    opened = open_recovery()
    expires_at = Time.iso8601(opened['expires_at']).to_i

    failing_join_response = join(opened['code'])
    request_to_fail = body_of(failing_join_response)
    store_error(request_to_fail['id'], 'code' => 'UnwrapFailed',
                                       'message' => '')
    failed_poll_response = poll(request_to_fail['id'])
    failed_request = body_of(failed_poll_response)
    assert_equal opened['expires_at'], failed_request['expires_at']

    join_response = join(opened['code'])
    joined = body_of(join_response)
    assert_equal opened['expires_at'], joined['expires_at']

    store_result(joined['id'])
    done_poll_response = poll(joined['id'])
    done_request = body_of(done_poll_response)
    assert_equal 'done', done_request['state']
    assert_equal opened['expires_at'], done_request['expires_at']

    # Redis drops the record and its request at that same second.
    request_key = DeviceRecovery.request_key(joined['id'])
    record_expiry = DeviceRecovery.redis.expiretime(own_record_key)
    request_expiry = DeviceRecovery.redis.expiretime(request_key)
    assert_equal expires_at, record_expiry
    assert_equal expires_at, request_expiry
  end

  it 'accepts the return key only as DER SubjectPublicKeyInfo' do
    opened = open_recovery()

    pkcs1_public_key = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(RETURN_KEY.n),
      OpenSSL::ASN1::Integer(RETURN_KEY.e),
    ]).to_der

    [
      RETURN_KEY.public_key.to_pem,
      pkcs1_public_key,
      RETURN_KEY.to_der,
      OpenSSL::PKey::RSA.new(2048).public_key.to_der,
    ].each do |return_key|
      encoded_key = Base64.strict_encode64(return_key)
      join_response = join(opened['code'], 'return_public_key' => encoded_key)
      join_error = error_code_of(join_response)
      assert_equal 400, join_response.status, return_key[0, 40].inspect
      assert_equal 'BadInput', join_error
    end
  end

  it 'refuses an oversized bundle and result' do
    opened = open_recovery()
    oversized_bundle = 'x' * (DeviceRecovery::MAX_BUNDLE_SIZE + 1)
    encoded_bundle = Base64.strict_encode64(oversized_bundle)
    bundle_join_response = join(opened['code'], 'bundle' => encoded_bundle)
    bundle_join_error = error_code_of(bundle_join_response)
    assert_equal 400, bundle_join_response.status
    assert_equal 'BadInput', bundle_join_error

    join_response = join(opened['code'])
    id = body_of(join_response)['id']
    oversized_result = 'x' * (DeviceRecovery::MAX_RESULT_SIZE + 1)
    act_as_key_service
    result_response = send_json(
      :put, "/v3/recovery/requests/#{ id }/result",
      'result' => Base64.strict_encode64(oversized_result))
    result_error = error_code_of(result_response)
    assert_equal 400, result_response.status
    assert_equal 'BadInput', result_error
  end

  it 'refuses a body that is not a JSON object' do
    ['[]', '7', '"text"'].each do |body|
      join_response = post('/v3/recovery/requests', body,
                           'CONTENT_TYPE' => 'application/json')
      join_error = error_code_of(join_response)
      assert_equal 400, join_response.status, body
      assert_equal 'BadInput', join_error
    end

    # JSON, but not marked as JSON.
    unmarked_body = { 'code' => WRONG_CODE }.to_json
    unmarked_response = post('/v3/recovery/requests', unmarked_body)
    unmarked_error = error_code_of(unmarked_response)
    assert_equal 400, unmarked_response.status
    assert_equal 'BadInput', unmarked_error
  end

  it 'records a key service error' do
    joined = queue_request()
    error_response = store_error(joined['id'], 'code' => 'ApprovalExpired',
                                               'message' => 'late')
    assert_200(error_response)
    stored_answer = body_of(error_response)
    assert_equal 'failed', stored_answer['state']

    poll_response = poll(joined['id'])
    polled_request = body_of(poll_response)
    assert_equal 'ApprovalExpired', polled_request['error']['code']
  end

  it 'keeps the first result' do
    joined = queue_request()
    result_response = store_result(joined['id'])
    assert_200(result_response)

    second_answer_response = store_error(joined['id'],
                                         'code' => 'UnwrapFailed',
                                         'message' => '')
    second_answer_error = error_code_of(second_answer_response)
    assert_equal 409, second_answer_response.status
    assert_equal 'WrongState', second_answer_error

    poll_response = poll(joined['id'])
    polled_request = body_of(poll_response)
    assert_equal 'done', polled_request['state']
  end

  it 'refuses a result together with an error' do
    joined = queue_request()
    act_as_key_service
    both_response = send_json(
      :put, "/v3/recovery/requests/#{ joined['id'] }/result",
      'result' => Base64.strict_encode64(ENCRYPTED_KEY),
      'error' => { 'code' => 'UnwrapFailed', 'message' => '' })
    both_error = error_code_of(both_response)
    assert_equal 400, both_response.status
    assert_equal 'BadInput', both_error
  end

  it 'counts a wrong code on a queued request' do
    joined = queue_request()
    queued_show_response = show_recovery()
    queued_recovery = body_of(queued_show_response)
    assert_equal 0, queued_recovery['wrong_codes']

    join_response = join(WRONG_CODE)
    assert_equal 404, join_response.status

    poll_response = poll(joined['id'])
    show_response = show_recovery()
    polled_request = body_of(poll_response)
    shown_recovery = body_of(show_response)
    assert_equal 'queued', polled_request['state']
    assert_equal 1, shown_recovery['wrong_codes']
  end

  it 'serves the key service only the organisations its client is allowed' do
    own_request = queue_request()
    other_request = join_other_organisation()
    all_queued_ids = queued_ids()

    # Opened perhaps in the same second, so in either order.
    both_ids = [own_request['id'], other_request['id']].sort
    sorted_queued_ids = all_queued_ids.sort
    assert_equal both_ids, sorted_queued_ids

    own_domains = PG::TextEncoder::Array.new.encode([own_domain])
    oauth2_client_db do |db|
      db.exec_params('UPDATE token_clients SET allowed_organisations = $1 ' \
                     'WHERE client_id = $2',
                     [own_domains, KEY_SERVICE_CLIENT])
    end

    own_queued_ids = queued_ids()
    other_result_response = store_result(other_request['id'])
    assert_equal [own_request['id']], own_queued_ids
    assert_equal 404, other_result_response.status
  end

  it 'refuses a key service error without a bounded message' do
    joined = queue_request()
    too_long = 'x' * (DeviceRecovery::MAX_TEXT_FIELD_SIZE + 1)

    [{ 'code' => 'UnwrapFailed' },
     { 'code' => 'UnwrapFailed', 'message' => too_long }].each do |error|
      answer_response = store_error(joined['id'], error)
      answer_error = error_code_of(answer_response)
      assert_equal 400, answer_response.status
      assert_equal 'BadInput', answer_error
    end
  end

  it 'opens the key service calls only with the key service scope' do
    joined = queue_request()
    result_path = "/v3/recovery/requests/#{ joined['id'] }/result"
    result_body = { 'result' => Base64.strict_encode64(ENCRYPTED_KEY) }

    # The same client, with a token of another scope it is allowed.
    act_as_key_service(OTHER_SCOPE)
    unscoped_queue_response = get('/v3/recovery/queue')
    unscoped_queue_error = error_code_of(unscoped_queue_response)
    unscoped_result_response = send_json(:put, result_path, result_body)
    unscoped_result_error = error_code_of(unscoped_result_response)
    assert_equal 401, unscoped_queue_response.status
    assert_equal 'InsufficientOAuth2Scope', unscoped_queue_error
    assert_equal 401, unscoped_result_response.status
    assert_equal 'InsufficientOAuth2Scope', unscoped_result_error

    act_as_key_service(KEY_SERVICE_SCOPE)
    scoped_queue_response = get('/v3/recovery/queue')
    scoped_result_response = send_json(:put, result_path, result_body)
    assert_200(scoped_queue_response)
    assert_200(scoped_result_response)
  end

  it 'refuses the key service calls to devices, owners, admins and users' do
    admin = PuavoRest::User.new(first_name: 'Alice', last_name: 'Admin',
                                username: 'alice', password: USER_PASSWORD,
                                roles: ['admin'],
                                school_dns: [@school.dn.to_s])
    admin.save!
    # .add_admin() is of the puavo-web model.
    admin_entry = User.find(:first, attribute: 'puavoId', value: admin.id)
    @school.add_admin(admin_entry)
    joined = queue_request()

    # Each is logged in, as the first call shows. The key service calls
    # need a token with the key service scope, which none has.
    act_as_device
    device_statuses = statuses_of_calls(joined['id'])
    act_as_owner
    owner_statuses = statuses_of_calls(joined['id'])
    act_as_user('alice')
    admin_statuses = statuses_of_calls(joined['id'])
    act_as_user('bob')
    user_statuses = statuses_of_calls(joined['id'])
    assert_equal [401, 401, 401], device_statuses
    assert_equal [200, 401, 401], owner_statuses
    assert_equal [200, 401, 401], admin_statuses
    assert_equal [200, 401, 401], user_statuses

    # Nothing got through: the request still waits.
    poll_response = poll(joined['id'])
    polled_request = body_of(poll_response)
    assert_equal 'queued', polled_request['state']
  end

  it 'slows polling further back in the queue' do
    numbers = (2..7).to_a
    numbers.each { |number| add_laptop(number) }
    hostnames = ['laptop1'] + numbers.map { |number| "laptop#{ number }" }
    serial_numbers = [SERIAL_NUMBER] +
                     numbers.map { |number| "SERIAL-#{ number }" }

    openings = open_in_order(hostnames)
    joins = openings.zip(serial_numbers).map do |opened, serial_number|
      join_response = join(opened['code'], 'serial_number' => serial_number)
      assert_equal 201, join_response.status, join_response.body
      body_of(join_response)
    end

    # The first polls at the shortest interval, the last every as many
    # seconds as its place in the queue.
    first_poll_response = poll(joins.first['id'])
    first_in_queue = body_of(first_poll_response)
    last_poll_response = poll(joins.last['id'])
    last_in_queue = body_of(last_poll_response)
    assert_equal 1, first_in_queue['queue_position']
    assert_equal DeviceRecovery::MIN_POLL_SECONDS,
                 first_in_queue['poll_seconds']
    assert_equal 7, last_in_queue['queue_position']
    assert_equal 7, last_in_queue['poll_seconds']
  end

  it 'counts only waiting requests in the queue position' do
    numbers = [2, 3, 4]
    numbers.each { |number| add_laptop(number) }
    hostnames = numbers.map { |number| "laptop#{ number }" } + ['laptop1']
    serial_numbers = numbers.map { |number| "SERIAL-#{ number }" } +
                     [SERIAL_NUMBER]

    openings = open_in_order(hostnames)
    joins = openings.zip(serial_numbers).map do |opened, serial_number|
      join_response = join(opened['code'], 'serial_number' => serial_number)
      body_of(join_response)
    end
    request_to_answer, request_to_cancel, _request_to_close,
      waiting_request = joins

    # Three opened earlier wait ahead of it.
    before_poll_response = poll(waiting_request['id'])
    waiting_before = body_of(before_poll_response)
    assert_equal 4, waiting_before['queue_position']

    store_result(request_to_answer['id'])
    delete_request(request_to_cancel['id'])
    act_as_owner
    delete('/v3/devices/laptop4/recovery')

    after_poll_response = poll(waiting_request['id'])
    queued_request_ids = queued_ids()
    waiting_after = body_of(after_poll_response)
    assert_equal 1, waiting_after['queue_position']
    assert_equal [waiting_request['id']], queued_request_ids
  end

  it 'drops the requests of expired recoveries from the queue' do
    add_laptop(2)
    add_laptop(3)
    waiting_request = queue_request('laptop2', 'SERIAL-2')

    # Opened so long ago that it expires soon, so it is ahead of the other
    # in the queue. The time left is long enough for its opening and join.
    seconds_left = 10
    opened_at = Time.now - DeviceRecovery::LIFETIME + seconds_left
    expiring_recovery = Timecop.freeze(opened_at) do
      open_recovery()
    end
    expiring_join_response = join(expiring_recovery['code'])
    assert_equal 201, expiring_join_response.status
    expiring_request = body_of(expiring_join_response)

    # Waits for an absolute time, so a slow test only waits less.
    expires_at = Time.iso8601(expiring_recovery['expires_at'])
    sleep_seconds = expires_at + 1 - Time.now
    sleep(sleep_seconds) if sleep_seconds.positive?

    # The expired id is still in the queue, and nothing counts or fetches it.
    expired_poll_response = poll(expiring_request['id'])
    waiting_poll_response = poll(waiting_request['id'])
    queued_request_ids = queued_ids()
    queue_size = DeviceRecovery.redis.zcard(DeviceRecovery::QUEUE_KEY)
    waiting_after = body_of(waiting_poll_response)
    assert_equal 404, expired_poll_response.status
    assert_equal 1, waiting_after['queue_position']
    assert_equal [waiting_request['id']], queued_request_ids
    assert_equal 2, queue_size

    # The next join removes it, so the queue stays bounded.
    later_request = queue_request('laptop3', 'SERIAL-3')
    later_queue_ids = DeviceRecovery.redis.zrange(DeviceRecovery::QUEUE_KEY,
                                                  0, -1)
    assert_equal [waiting_request['id'], later_request['id']], later_queue_ids
  end
end

end
