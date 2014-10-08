###
Dependencies
###
_          = require 'lodash'
async      = require 'async'
sailor     = require 'sailorjs'
actionUtil = sailor.actionUtil

###*
Add Record To Collection

post  /:modelIdentity/:id/:collectionAttr/:childid
/:modelIdentity/:id/:collectionAttr/add/:childid

Associate one record with the collection attribute of another.
e.g. add a Horse named "Jimmy" to a Farm's "animals".
If the record being added has a primary key value already, it will
just be linked.  If it doesn't, a new record will be created, then
linked appropriately.  In either case, the association is bidirectional.

@param {Integer|String} parentid  - the unique id of the parent record
@param {Integer|String} id    [optional]
- the unique id of the child record to add
Alternatively, an object WITHOUT a primary key may be POSTed
to this endpoint to create a new child record, then associate
it with the parent.

@option {String} model  - the identity of the model
@option {String} alias  - the name of the association attribute (aka "alias")
###
module.exports = (req, res) ->

  # Ensure a model and alias can be deduced from the request.
  Model    = actionUtil.parseModel(req)
  relation = req.options.alias
  return res.serverError(new Error("Missing required route option, `req.options.alias`.")) unless relation

  # The primary key of the parent record
  parentPk = req.param("parentid")

  # Get the model class of the child in order to figure out the name of
  # the primary key attribute.
  associationAttr = _.findWhere(Model.associations,
    alias: relation
  )
  ChildModel = sails.models[associationAttr.collection]
  childPkAttr = ChildModel.primaryKey

  # The child record to associate is defined by either...
  child = undefined

  # ...a primary key:
  supposedChildPk = actionUtil.parsePk(req)
  if supposedChildPk
    child = {}
    child[childPkAttr] = supposedChildPk

  # ...or an object of values:
  else
    req.options.values = req.options.values or {}
    req.options.values.blacklist = req.options.values.blacklist or [
      "limit"
      "skip"
      "sort"
      "id"
      "parentid"
    ]
    child = actionUtil.parseValues(req)
  res.badRequest "You must specify the record to add (either the primary key of an existing record to link, or a new object without a primary key which will be used to create a record then link it.)"  unless child
  createdChild = false
  async.auto

    # Look up the parent record
    parent: (cb) ->
      Model.findOne(parentPk).exec foundParent = (err, parentRecord) ->
        return cb(err)  if err
        return cb(status: 404)  unless parentRecord
        return cb(status: 404)  unless parentRecord[relation]
        cb null, parentRecord
        return

      return


    # If a primary key was specified in the `child` object we parsed
    # from the request, look it up to make sure it exists.  Send back its primary key value.
    # This is here because, although you can do this with `.save()`, you can't actually
    # get ahold of the created child record data, unless you create it first.
    actualChildPkValue: [
      "parent"
      (cb) ->

        # Below, we use the primary key attribute to pull out the primary key value
        # (which might not have existed until now, if the .add() resulted in a `create()`)

        # If the primary key was specified for the child record, we should try to find
        # it before we create it.

        # Didn't find it?  Then try creating it.

        # Otherwise use the one we found.

        # Otherwise, it must be referring to a new thing, so create it.

        # Create a new instance and send out any required pubsub messages.
        createChild = ->
          ChildModel.create(child).exec createdNewChild = (err, newChildRecord) ->
            return cb(err)  if err
            if req._sails.hooks.pubsub
              if req.isSocket
                ChildModel.subscribe req, newChildRecord
                ChildModel.introduce newChildRecord
              ChildModel.publishCreate newChildRecord, not req.options.mirror and req
            createdChild = true
            cb null, newChildRecord[childPkAttr]

          return
        if child[childPkAttr]
          ChildModel.findOne(child[childPkAttr]).exec foundChild = (err, childRecord) ->
            return cb(err)  if err
            return createChild()  unless childRecord
            cb null, childRecord[childPkAttr]

        else
          return createChild()
    ]

    # Add the child record to the parent's collection
    add: [
      "parent"
      "actualChildPkValue"
      (cb, async_data) ->
        try

          # `collection` is the parent record's collection we
          # want to add the child to.
          collection = async_data.parent[relation]
          collection.add async_data.actualChildPkValue
          return cb()

        # Ignore `insert` errors
        catch err

          # if (err && err.type !== 'insert') {
          return cb(err)  if err

          # else if (err) {
          #   // if we made it here, then this child record is already
          #   // associated with the collection.  But we do nothing:
          #   // `add` is idempotent.
          # }
          return cb()
    ]

  # Save the parent record
  , readyToSave = (err, async_data) ->
    return res.negotiate(err)  if err
    async_data.parent.save saved = (err) ->

      # Ignore `insert` errors for duplicate adds
      # (but keep in mind, we should not publishAdd if this is the case...)
      isDuplicateInsertError = (err and typeof err is "object" and err.length and err[0] and err[0].type is "insert")
      return res.negotiate(err)  if err and not isDuplicateInsertError

      # Only broadcast an update if this isn't a duplicate `add`
      # (otherwise connected clients will see duplicates)
      if not isDuplicateInsertError and req._sails.hooks.pubsub

        # Subscribe to the model you're adding to, if this was a socket request
        Model.subscribe req, async_data.parent  if req.isSocket

        # Publish to subscribed sockets
        Model.publishAdd async_data.parent[Model.primaryKey], relation, async_data.actualChildPkValue, not req.options.mirror and req,
          noReverse: createdChild


      # Finally, look up the parent record again and populate the relevant collection.
      # TODO: populateEach
      Model.findOne(parentPk).populate(relation).exec (err, matchingRecord) ->
        return res.serverError(err)  if err
        return res.serverError() unless matchingRecord
        return res.serverError() unless matchingRecord[relation]
        res.created matchingRecord
