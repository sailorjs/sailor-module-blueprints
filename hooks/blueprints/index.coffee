## -- Exports -------------------------------------------------------------

module.exports = (sails) ->
  initialize: (cb) ->
    sails.modules.shield 'sailor-module-response'
    cb()
