###
Dependencies
###
sailor     = require 'sailorjs'
util       = require 'util'
actionUtil = sailor.actionUtil

###*
Populate (or "expand") an association

get /model/:parentid/relation
get /model/:parentid/relation/:id

@param {Integer|String} parentid  - the unique id of the parent instance
@param {Integer|String} id  - the unique id of the particular child instance you'd like to look up within this relation
@param {Object} where       - the find criteria (passed directly to the ORM)
@param {Integer} limit      - the maximum number of records to send back (useful for pagination)
@param {Integer} skip       - the number of records to skip (useful for pagination)
@param {String} sort        - the order of returned records, e.g. `name ASC` or `age DESC`

@option {String} model  - the identity of the model
@option {String} alias  - the name of the association attribute (aka "alias")
###
module.exports = expand = (req, res) ->
  Model    = actionUtil.parseModel(req)
  relation = req.options.alias
  return res.serverError()  if not relation or not Model

  # Allow customizable blacklist for params.
  req.options.criteria = req.options.criteria or {}
  req.options.criteria.blacklist = req.options.criteria.blacklist or [
    "limit"
    "skip"
    "sort"
    "id"
    "parentid"
  ]
  parentPk = req.param("parentid")

  # Determine whether to populate using a criteria, or the
  # specified primary key of the child record, or with no
  # filter at all.
  childPk = actionUtil.parsePk(req)
  where = (if childPk then [childPk] else actionUtil.parseCriteria(req))
  Model.findOne(parentPk).populate(relation,
    where: where
    skip: actionUtil.parseSkip(req)
    limit: actionUtil.parseLimit(req)
    sort: actionUtil.parseSort(req)
  ).exec found = (err, matchingRecord) ->
    return res.serverError(err)  if err
    return res.notFound("No record found with the specified id.")  unless matchingRecord
    return res.notFound(util.format("Specified record (%s) is missing relation `%s`", parentPk, relation))  unless matchingRecord[relation]

    # Subcribe to instance, if relevant
    # TODO: only subscribe to populated attribute- not the entire model
    if sails.hooks.pubsub and req.isSocket
      Model.subscribe req, matchingRecord
      actionUtil.subscribeDeep req, matchingRecord
    res.ok matchingRecord[relation]
