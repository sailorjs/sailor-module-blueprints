###
Module dependencies
###
sailor     = require 'sailorjs'
actionUtil = sailor.actionUtil
translate  = sailor.translate
validator  = sailor.validator
errorify   = sailor.errorify

###
Create Record

post /:modelIdentity

An API call to find and return a single model instance from the data adapter
using the specified criteria.  If an id was specified, just the instance with
that unique id will be returned.

Optional:
@param {String} callback - default jsonp callback param (i.e. the name of the js function returned)
@param {*} * - other params will be used as `values` in the create
###
module.exports = (req, res) ->
  Model = actionUtil.parseModel(req)

  # Create data object (monolithic combination of all parameters)
  # Omit the blacklisted params (like JSONP callback param, etc.)
  data = actionUtil.parseValues(req)

  # Create new instance of model using data from params
  Model.create(data).populateAll().exec (err, newInstance) ->

    # Differentiate between waterline-originated validation errors
    # and serious underlying issues. Respond with badRequest if a
    # validation error is encountered, w/ validation info.
    return res.negotiate(err)  if err

    # Use find method to return the model for the populate option
    Model.findOne(newInstance.id).populateAll().exec (err, newInstance) ->

      # If we have the pubsub hook, use the model class's publish method
      # to notify all subscribers about the created item
      if req._sails.hooks.pubsub
        if req.isSocket
          Model.subscribe req, newInstance
          Model.introduce newInstance
        Model.publishCreate newInstance, not req.options.mirror and req

      res.status 201
      res.ok newInstance
