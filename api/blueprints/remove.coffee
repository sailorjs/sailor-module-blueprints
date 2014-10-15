###
Dependencies
###
_          = require 'lodash'
sailor     = require 'sailorjs'
actionUtil = sailor.actionUtil

###*
Remove a member from an association

@param {Integer|String} parentid  - the unique id of the parent record
@param {Integer|String} id  - the unique id of the child record to remove

@option {String} model  - the identity of the model
@option {String} alias  - the name of the association attribute (aka "alias")
###
module.exports = remove = (req, res) ->

  # Ensure a model and alias can be deduced from the request.
  Model    = actionUtil.parseModel(req)
  relation = req.options.alias
  return res.serverError(new Error("Missing required route option, `req.options.alias`."))  unless relation

  # The primary key of the parent record
  parentPk = req.param("parentid")

  # Get the model class of the child in order to figure out the name of
  # the primary key attribute.
  associationAttr = _.findWhere(Model.associations,
    alias: relation
  )
  ChildModel = sails.models[associationAttr.collection]
  childPkAttr = ChildModel.primaryKey

  # The primary key of the child record to remove
  # from the aliased collection
  childPk = actionUtil.parsePk(req)
  Model.findOne(parentPk).exec found = (err, parentRecord) ->
    return res.serverError(err)  if err
    return res.notFound()  unless parentRecord
    return res.notFound()  unless parentRecord[relation]
    parentRecord[relation].remove childPk
    parentRecord.save (err) ->
      return res.negotiate(err)  if err

      # TODO: use populateEach util instead
      Model.findOne(parentPk).populate(relation).exec found = (err, parentRecord) ->
        return res.serverError(err)  if err
        return res.serverError()  unless parentRecord
        return res.serverError()  unless parentRecord[relation]
        return res.serverError()  unless parentRecord[Model.primaryKey]

        # If we have the pubsub hook, use the model class's publish method
        # to notify all subscribers about the removed item
        Model.publishRemove parentRecord[Model.primaryKey], relation, childPk, not sails.config.blueprints.mirror and req  if sails.hooks.pubsub
        res.ok parentRecord
