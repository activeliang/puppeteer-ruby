# providing #valueFromRemoteObject, #releaseObject
class Puppeteer::RemoteObject
  include Puppeteer::DebugPrint
  using Puppeteer::AsyncAwaitBehavior

  # @param payload [Hash]
  def initialize(payload)
    @object_id = payload["objectId"]
    @sub_type = payload["subtype"]
    @unserializable_value = payload["unserializableValue"]
    @value = payload["value"]
  end

  attr_reader :sub_type

  # @return [Future<Puppeteer::RemoteObject|nil>]
  def evaluate_self(client)
    # ported logic from JSHandle#json_value.

    # original logic:
    #   if (this._remoteObject.objectId) {
    #     const response = await this._client.send('Runtime.callFunctionOn', {
    #       functionDeclaration: 'function() { return this; }',
    #       objectId: this._remoteObject.objectId,
    #       returnByValue: true,
    #       awaitPromise: true,
    #     });
    #     return helper.valueFromRemoteObject(response.result);
    #   }

    if @object_id
      params = {
        'functionDeclaration': 'function() { return this; }',
        'objectId': @object_id,
        'returnByValue': true,
        'awaitPromise': true,
      }
      response = client.send_message("Runtime.callFunctionOn", params)
      Puppeteer::RemoteObject.new(response["result"])
    else
      nil
    end
  end

  # used in JSHandle#properties
  def properties(client)
    # original logic:
    #   const response = await this._client.send('Runtime.getProperties', {
    #     objectId: this._remoteObject.objectId,
    #     ownProperties: true
    #   });
    client.send_message('Runtime.getProperties', objectId: @object_id, ownProperties: true)
  end

  # used in ElementHandle#content_frame
  def node_info(client)
    client.send_message("DOM.describeNode", objectId: @object_id)
  end

  # helper#valueFromRemoteObject
  def value
    if @unserializable_value
      # if (remoteObject.type === 'bigint' && typeof BigInt !== 'undefined')
      #   return BigInt(remoteObject.unserializableValue.replace('n', ''));
      # switch (remoteObject.unserializableValue) {
      #   case '-0':
      #     return -0;
      #   case 'NaN':
      #     return NaN;
      #   case 'Infinity':
      #     return Infinity;
      #   case '-Infinity':
      #     return -Infinity;
      #   default:
      #     throw new Error('Unsupported unserializable value: ' + remoteObject.unserializableValue);
      # }
      raise NotImplementedError.new("unserializable_value is not implemented yet")
    else
      @value
    end
  end

  # @param client [Puppeteer::CDPSession]
  def release(client)
    return unless @object_id

    begin
      client.send_message('Runtime.releaseObject',
        objectId: @object_id,
      )
    rescue => err
      # Exceptions might happen in case of a page been navigated or closed.
      # Swallow these since they are harmless and we don't leak anything in this case.
      debug_puts(err)
    end

    nil
  end

  # @param client [Puppeteer::CDPSession]
  async def async_release(client)
    release(client)
  end

  def converted_arg
    # ported logic from ExecutionContext#convertArgument
    # https://github.com/puppeteer/puppeteer/blob/master/lib/ExecutionContext.js
    #
    # Original logic:
    # if (objectHandle._remoteObject.unserializableValue)
    #   return { unserializableValue: objectHandle._remoteObject.unserializableValue };
    # if (!objectHandle._remoteObject.objectId)
    #   return { value: objectHandle._remoteObject.value };
    # return { objectId: objectHandle._remoteObject.objectId };

    if @unserializable_value
      { unserializableValue: @unserializable_value }
    elsif @object_id
      { objectId: @object_id }
    else
      { value: value }
    end
  end
end
