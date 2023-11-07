# Base controller class for all mass operations. Do not put actual mass operations
# code in this file. Instead, derive a controller class and put it in its own file
# (just like Rails wants it). There are no publicly usable/callable methods here.

class MassOperationsController < ApplicationController
  include Puavo::Integrations     # request ID generation

  def prepare
    @request_id = generate_synchronous_call_id
    data = JSON.parse(request.body.read)
    @operation = data['operation']
    @single_shot = data.fetch('singleShot', false)
    @parameters = data['parameters'] || {}
    @rows = data['rows']
  end

  def process_rows(&block)
    logger.info "[#{@request_id}] Starting a mass operation; operation=\"#{@operation}\", single shot=#{@single_shot}, parameters=#{@parameters.inspect}, items=#{@rows.count}"
    out = []

    @rows.each do |row|
      # Copy back the fields SuperTable needs for updating the table
      o = {
        'index' => row['index'],
        'id' => row['id']
      }

      # Call the user-supplied processing function. Per-item data argument ('data') is optional.
      # The callback returns a three-item array: status, error message, return data (use the
      # success/fail helper methods for these). Only the first is actually required. Message is
      # needed only if the status is not true (indicating an error state); the message is displayed
      # in the interface. Data is optional and will be passed back to the caller, if present.
      status, message, data = block.call(row['id'], row.fetch('data', nil))
      o['status'] = status

      # Optional, only used if 'status' is false to minimize the amount of network traffic
      o['message'] = message if message
      o['data'] = data if data

      out << o
    end

    logger.info "[#{@request_id}] Mass operation complete"

    # Construct a successfull return value
    {
      ok: true,
      rows: out,
      request_id: @request_id
    }
  end

  # Operation return value builders
  def success(message: nil, data: nil)
    [true, message, data]
  end

  def fail(message: nil, data: nil)
    [false, message, data]
  end
end
