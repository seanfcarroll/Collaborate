Collaborate.CollaborativeAttribute = class CollaborateAttribute
  constructor: (@collaborate, @attribute) ->
    throw new Exception('You must specify an attribute to collaboratively edit') unless @attribute

    new Collaborate.Events(this)

    @documentId = @collaborate.documentId
    @cable = new Collaborate.AttributeCable @, @collaborate.cable, @attribute

    @state = new Synchronized(this)

  localOperation: (operation) =>
    return if operation.isNoop()

    @state.localOperation(operation)

  remoteOperation: (data) =>
    @state.remoteOperation(data)

    @trigger 'remoteOperation', data.operation

  receiveAck: (data) =>
    @state.receiveAck(data)

  # States based around https://github.com/Operational-Transformation/ot.js/blob/15d4e7f/lib/client.js#L63
  class State
    constructor: (collaborativeAttribute) ->
      @collaborativeAttribute = collaborativeAttribute

  class Synchronized extends State
    localOperation: (operation) =>
      @collaborativeAttribute.cable.sendOperation
        operation: operation

      @collaborativeAttribute.state = new AwaitingAck(@collaborativeAttribute, operation)

    receiveAck: (data) ->
      console.error "Received an ack for version #{data.version} whilst in Synchronized state."

    remoteOperation: (data) ->
      # Noop. We don't need to transform the operation as it can be applied
      # happily

  class AwaitingAck extends State
    constructor: (collaborativeAttribute, @operation) ->
      super

    localOperation: (operation) =>
      @collaborativeAttribute.state = new AwaitingWithBuffer(@collaborativeAttribute, @operation, operation)

    receiveAck: (data) =>
      @collaborativeAttribute.state = new Synchronized(@collaborativeAttribute)

    remoteOperation: (data) =>
      # Ok. We have something to do...

      # First, transform our pending operation and the received operation
      pair = ot.TextOperation.transform(@operation, data.operation)

      @operation = pair[0]
      data.operation = pair[1]

  class AwaitingWithBuffer extends State
    constructor: (collaborativeAttribute, @operation, @buffer) ->
      super

    localOperation: (operation) =>
      @buffer = @buffer.compose(operation)

    receiveAck: (data) =>
      @collaborativeAttribute.cable.sendOperation
        operation: @buffer

      @collaborativeAttribute.state = new AwaitingAck(@collaborativeAttribute, @buffer)

    remoteOperation: (data) =>
      # First, transform our pending operation and the received operation
      pair = ot.TextOperation.transform(@operation, data.operation)

      @operation = pair[0]
      data.operation = pair[1]

      # Transform again...
      pair = ot.TextOperation.transform(@buffer, data.operation)

      @buffer = pair[0]
      data.operation = pair[1]