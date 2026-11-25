# The remote recovery of one device that failed to unlock its disk. An
# organisation owner opens it and tells the person its code, the device
# joins with the code and its request, and the key service answers the
# request. A recovery lives in Redis and ends by expiry.

require 'digest'
require 'securerandom'

module PuavoRest

class DeviceRecovery
  # Times in seconds. A record, its approval and its result all end 3
  # days after the opening, so a code that arrives late still works.
  LIFETIME = 3 * 24 * 60 * 60                  # 3 days

  # The poll interval in seconds is the queue position, within these. The
  # first in the queue sees its result soon without a call every second,
  # and a device far back still shows its new place every few minutes.
  MIN_POLL_SECONDS = 5                         # 5 seconds
  MAX_POLL_SECONDS = 300                       # 5 minutes

  # No Y and Z, which swap places between keyboard layouts.
  CODE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWX'.chars.freeze

  # 30 symbols in 8 places give about 6.6 * 10^11 codes. With 10 wrong
  # codes allowed per recovery, a guesser succeeds about once in 66
  # billion recoveries. Eight characters are still easy to read out over
  # the phone and type.
  CODE_LENGTH = 8
  MAX_WRONG_CODES = 10
  REQUEST_ID_BYTES = 32                        # 43 characters of base64

  # The most requests the key service gets per fetch, so one answer stays
  # under 200 KB.
  MAX_FETCHED_REQUESTS = 50

  # How long a lock holds at most. Far longer than the few Redis calls made
  # under it, yet a crashed holder frees the recovery soon.
  LOCK_MILLISECONDS = 2000                     # 2 seconds

  # Sizes in bytes. Serial numbers, organisation ids and error codes are
  # short, and the limit bounds what a caller without credentials stores.
  MAX_TEXT_FIELD_SIZE = 256
  MAX_BUNDLE_SIZE = 8 * 1024                   # 8 KiB

  # An RSA 3072 public key is about 420 bytes as DER.
  MAX_RETURN_KEY_SIZE = 1024                   # 1 KiB
  RETURN_KEY_BITS = 3072
  MAX_RESULT_SIZE = RETURN_KEY_BITS / 8        # 384 bytes
  RETURN_KEY_EXPONENT = 65537

  module State
    OPEN = 'open'
    QUEUED = 'queued'
    DONE = 'done'
    FAILED = 'failed'
  end

  # The outcome of a join: a new request was queued, or the same request
  # was found already queued, sent again by a device whose answer was lost.
  module JoinOutcome
    NEW = 'new'
    REPEATED = 'repeated'
  end

  # The fields of a joined request, dropped when the recovery opens again.
  REQUEST_FIELDS = %w[id organisation_id digest approval bundle
                      return_public_key result error].freeze

  # Queued request ids, scored by the expiry of their record, so the ids of
  # expired records are found without reading them. The earliest opened
  # recovery is first.
  QUEUE_KEY = 'queue'

  # @param fields [Hash] the stored fields of the recovery
  def initialize(fields)
    @fields = fields
  end

  # @param name [String] a stored field, such as 'state' or 'id'
  # @return the value of the field, or nil
  def [](name)
    @fields[name]
  end

  # @return [Redis::Namespace] the Redis store of recoveries
  def self.redis
    Redis::Namespace.new('recovery', redis: REDIS_CONNECTION)
  end

  # The request digest as the device computes it.
  # @param bundle [String] the bundle, binary
  # @param return_public_key [String] the return key, binary DER
  # @return [String] the digest in hexadecimal
  def self.digest(bundle, return_public_key)
    Digest::SHA256.hexdigest(Digest::SHA256.digest(bundle) +
                             Digest::SHA256.digest(return_public_key))
  end

  # Opens a recovery of the device with a new code. An earlier recovery
  # of the device ends.
  # @param domain [String] the organisation domain of the device
  # @param serial_number [String] the serial number of the device
  # @param opened_by [String] the user name of the owner who opens it
  # @return [DeviceRecovery] the opened recovery
  def self.open(domain, serial_number, opened_by)
    now = Time.now.to_i
    recovery = new(
      'domain' => domain,
      'serial_number' => serial_number,
      'state' => State::OPEN,
      'code' => new_code,
      'opened_by' => opened_by,
      'wrong_codes' => 0,
      'created_at' => now,
      'expires_at' => now + LIFETIME,
    )

    lock(domain, serial_number) do |earlier|
      earlier&.delete
      recovery.save
    end

    recovery
  end

  # @return [String] a new random code
  private_class_method def self.new_code
    Array.new(CODE_LENGTH) do
      CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.size)]
    end.join
  end

  # The Redis key of the recovery record of a device.
  # @param domain [String] the organisation domain of the device
  # @param serial_number [String] the serial number of the device
  # @return [String]
  def self.record_key(domain, serial_number)
    "device:#{ domain }:#{ serial_number }"
  end

  # The Redis key that leads from a request id to the record key of its
  # recovery.
  # @param id [String] the request id
  # @return [String]
  def self.request_key(id)
    "request:#{ id }"
  end

  # @param key [String] the record key
  # @return [DeviceRecovery, nil] the recovery, or nil when there is none
  private_class_method def self.read_record(key)
    stored_json = redis.get(key)

    # Never opened, or expired: the caller answers 404.
    return nil if stored_json.nil?

    new(JSON.parse(stored_json))
  end

  # The recovery of a device.
  # @param domain [String] the organisation domain of the device
  # @param serial_number [String] the serial number of the device
  # @return [DeviceRecovery]
  # @raise [RecoveryRequestNotFound] when the device has no recovery
  def self.find(domain, serial_number)
    recovery = read_record(record_key(domain, serial_number))
    raise RecoveryRequestNotFound, user: 'no such recovery' if recovery.nil?

    recovery
  end

  # The recovery that holds the request.
  # @param id [String] the request id
  # @return [DeviceRecovery]
  # @raise [RecoveryRequestNotFound] when no recovery holds the request
  def self.find_by_request_id(id)
    key = redis.get(request_key(id.to_s))
    recovery = key && read_record(key)
    if recovery.nil? || recovery['id'] != id
      raise RecoveryRequestNotFound, user: 'no such recovery request'
    end

    recovery
  end

  # Runs the block with the recovery of the device locked, so two callers
  # never change it at once.
  # @param domain [String] the organisation domain of the device
  # @param serial_number [String] the serial number of the device
  # @yieldparam recovery [DeviceRecovery, nil] the locked recovery, or nil
  #   when the device has none
  # @return [DeviceRecovery, nil] the recovery the block got
  # @raise [InternalError] when locking fails
  def self.lock(domain, serial_number)
    recovery = nil
    name = "recovery:lock:#{ record_key(domain, serial_number) }"

    DISTRIBUTED_LOCK.lock(name, LOCK_MILLISECONDS) do |lock|
      raise InternalError, user: 'failed to lock the recovery' unless lock

      recovery = read_record(record_key(domain, serial_number))
      yield recovery
    end

    recovery
  end

  # Runs the block with the recovery that holds the request locked.
  # @param id [String] the request id
  # @yieldparam recovery [DeviceRecovery] the locked recovery
  # @return [DeviceRecovery] the recovery
  # @raise [RecoveryRequestNotFound] when no recovery holds the request
  def self.lock_by_request_id(id)
    unlocked_recovery = find_by_request_id(id)
    lock(unlocked_recovery['domain'],
         unlocked_recovery['serial_number']) do |recovery|
      if recovery.nil? || recovery['id'] != id
        raise RecoveryRequestNotFound, user: 'no such recovery request'
      end

      yield recovery
    end
  end

  # Ends the recovery of the device.
  # @param domain [String] the organisation domain of the device
  # @param serial_number [String] the serial number of the device
  # @raise [RecoveryRequestNotFound] when the device has no recovery
  def self.close(domain, serial_number)
    lock(domain, serial_number) do |recovery|
      raise RecoveryRequestNotFound, user: 'no such recovery' if recovery.nil?

      recovery.delete
    end
  end

  # The oldest queued requests, as many as one fetch takes.
  # @param domains [Array<String>, nil] the organisation domains to fetch
  #   from, or nil for all organisations
  # @return [Array<DeviceRecovery>] the recoveries, earliest opened first
  def self.oldest_queued_requests(domains)
    batch = []
    unexpired_ids = redis.zrangebyscore(QUEUE_KEY, "(#{ Time.now.to_i }",
                                        '+inf')

    unexpired_ids.each do |id|
      break if batch.size >= MAX_FETCHED_REQUESTS

      # A record that expired since the queue was read.
      begin
        recovery = find_by_request_id(id)
      rescue RecoveryRequestNotFound
        next
      end

      next if domains && !domains.include?(recovery['domain'])

      batch << recovery
    end

    batch
  end

  # Queues the request of the device. The code is compared first, in every
  # state. A wrong code is counted, and too many close the recovery.
  # @param code [String] the code as typed
  # @param request [Hash] 'organisation_id', and 'bundle' and
  #   'return_public_key' as binary
  # @return [String] JoinOutcome::NEW or JoinOutcome::REPEATED
  # @raise [RecoveryRequestNotFound] when the code is wrong
  # @raise [CodeInUse] when another request is queued
  # @raise [WrongState] when the recovery takes no request
  def join(code, request)
    unless code_matches?(code)
      count_wrong_code
      raise RecoveryRequestNotFound, user: 'no such recovery'
    end

    digest = self.class.digest(request['bundle'],
                               request['return_public_key'])

    case @fields['state']
    when State::OPEN, State::FAILED
      # A new request. In a failed recovery it replaces the failed one.
      queue_new_request(request, digest)
      JoinOutcome::NEW
    when State::QUEUED
      # The first join wins, so somebody else who got the code and a copy
      # of the bundle never takes the request over unseen. A device whose
      # answer was lost sends the same request again.
      if @fields['digest'] != digest
        raise CodeInUse, user: 'the code is already in use'
      end

      JoinOutcome::REPEATED
    when State::DONE
      # The request has its answer, so the recovery takes no other.
      raise WrongState, user: 'the recovery is done'
    end
  end

  # The device's delete of its request.
  def cancel
    case @fields['state']
    when State::QUEUED, State::FAILED
      # The recovery opens again for the same code.
      cancelled_id = @fields['id']
      drop_request
      save { |transaction| remove_request(transaction, cancelled_id) }
    when State::DONE
      # The device has its result, so the recovery ends.
      delete
    end
  end

  # Answers the queued request with a result for the device.
  # @param result [String] the result, base64
  # @raise [WrongState] when no request is queued
  def store_result(result)
    store_answer(State::DONE, 'result' => result)
  end

  # Answers the queued request with an error for the device.
  # @param error [Hash] 'code' and 'message'
  # @raise [WrongState] when no request is queued
  def store_error(error)
    store_answer(State::FAILED, 'error' => error)
  end

  # Removes the recovery and its request from Redis.
  def delete
    self.class.redis.multi do |transaction|
      remove_request(transaction, @fields['id'])
      transaction.del(record_key)
    end
  end

  # Writes the recovery to Redis, to expire at its expiry. The writes of the
  # block go in the same transaction, so no reader sees a record without
  # its queue entries.
  # @yieldparam transaction [Redis::Namespace] for the caller's queue
  #   writes
  def save
    self.class.redis.multi do |transaction|
      transaction.set(record_key, @fields.to_json,
                      exat: @fields['expires_at'])
      if @fields['id']
        transaction.set(self.class.request_key(@fields['id']), record_key,
                        exat: @fields['expires_at'])
      end

      yield transaction if block_given?
    end
  end

  # What the owner sees of the recovery.
  # @return [Hash]
  def owner_view
    view = {
      'state' => @fields['state'],
      'serial_number' => @fields['serial_number'],
      'opened_by' => @fields['opened_by'],
      'created_at' => Time.at(@fields['created_at']).utc.iso8601,
      'expires_at' => Time.at(@fields['expires_at']).utc.iso8601,
      'wrong_codes' => @fields['wrong_codes'],
    }

    view['code'] = @fields['code'] if @fields['state'] == State::OPEN
    view['queue_position'] = queue_position if @fields['state'] == State::QUEUED

    view
  end

  # What the device sees of its request.
  # @return [Hash]
  def device_view
    view = {
      'id' => @fields['id'],
      'state' => @fields['state'],
      'expires_at' => Time.at(@fields['expires_at']).utc.iso8601,
      'approval' => @fields['approval'],
    }

    case @fields['state']
    when State::QUEUED
      position = queue_position

      # No position only at the moment the record expires.
      poll_seconds = (position || MIN_POLL_SECONDS)
                     .clamp(MIN_POLL_SECONDS, MAX_POLL_SECONDS)
      view.merge!('queue_position' => position,
                  'poll_seconds' => poll_seconds)
    when State::DONE
      view.merge!('result' => @fields['result'],
                  'poll_seconds' => MIN_POLL_SECONDS)
    when State::FAILED
      view.merge!('error' => @fields['error'],
                  'poll_seconds' => MIN_POLL_SECONDS)
    end

    view
  end

  # What the key service fetches from the queue.
  # @return [Hash]
  def key_service_view
    @fields.slice('id', 'organisation_id', 'serial_number', 'bundle',
                  'return_public_key', 'approval')
  end

  private

  # The place of the queued request, 1 for the next one the key service
  # fetches. The ids of expired records ahead of it are not counted.
  # @return [Integer, nil] the place, or nil when the id is gone from the
  #   queue
  def queue_position
    rank, expired_count = self.class.redis.multi do |transaction|
      transaction.zrank(QUEUE_KEY, @fields['id'])
      transaction.zcount(QUEUE_KEY, 0, Time.now.to_i)
    end
    return nil if rank.nil?

    rank + 1 - expired_count
  end

  # Queues a new request in place of any earlier one.
  # @param request [Hash] as for join
  # @param digest [String] the request digest
  def queue_new_request(request, digest)
    replaced_id = @fields['id']
    drop_request
    @fields.merge!(
      'id' => SecureRandom.urlsafe_base64(REQUEST_ID_BYTES),
      'organisation_id' => request['organisation_id'],
      'digest' => digest,
      'bundle' => Base64.strict_encode64(request['bundle']),
      'return_public_key' =>
        Base64.strict_encode64(request['return_public_key']),
    )

    @fields.merge!('state' => State::QUEUED,
                   'approval' => RecoveryApproval.sign(self))

    save do |transaction|
      remove_request(transaction, replaced_id)

      # The ids of expired records go where the queue grows, so it stays
      # bounded and its readers only read.
      transaction.zremrangebyscore(QUEUE_KEY, 0, Time.now.to_i)
      transaction.zadd(QUEUE_KEY, @fields['expires_at'], @fields['id'])
    end
  end

  # Forgets the fields of the joined request and opens the recovery again.
  def drop_request
    REQUEST_FIELDS.each { |name| @fields.delete(name) }
    @fields['state'] = State::OPEN
  end

  # @param state [String] the State the recovery must be in
  # @raise [WrongState] when it is in another
  def require_state(state)
    return if @fields['state'] == state

    raise WrongState, user: "the recovery is #{ @fields['state'] }"
  end

  # @return [String] the Redis key of this recovery's record
  def record_key
    self.class.record_key(@fields['domain'], @fields['serial_number'])
  end

  # Takes the code as people type it: any case, spaces ignored.
  # @param code [String] the code as typed
  # @return [Boolean] true when it is the code of the recovery
  def code_matches?(code)
    typed_code = code.to_s.upcase.delete(' ')
    Rack::Utils.secure_compare(@fields['code'], typed_code)
  end

  # Counts a wrong code against the recovery and closes it at the last one
  # allowed.
  def count_wrong_code
    @fields['wrong_codes'] += 1
    return delete if @fields['wrong_codes'] >= MAX_WRONG_CODES

    save
  end

  # Answers the queued request and takes it off the queue.
  # @param state [String] State::DONE or State::FAILED
  # @param answer [Hash] 'result' or 'error', kept for the device
  # @raise [WrongState] when no request is queued
  def store_answer(state, answer)
    require_state(State::QUEUED)
    @fields.delete('bundle')
    @fields.delete('return_public_key')
    @fields.merge!(answer)
    @fields['state'] = state

    save do |transaction|
      transaction.zrem(QUEUE_KEY, @fields['id'])
    end
  end

  # Removes the keys of a request.
  # @param transaction [Redis::Namespace] the transaction to remove in
  # @param id [String, nil] the request id, or nil for no request
  def remove_request(transaction, id)
    return if id.nil?

    transaction.del(self.class.request_key(id))
    transaction.zrem(QUEUE_KEY, id)
  end
end

end
