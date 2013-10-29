Vendue = require './vendue'
fs = require 'fs'

forEachAccount = (fn) ->
  fs.readFile "accounts.json", (err, content) ->
    accounts = JSON.parse content
    for account in accounts
      continue if not account.enabled
      fn(account)


exports.run = run = ->
  forEachAccount (account) ->
    new Vendue(account).login (success) ->
      console.log "starting account #{@user_id}..."
      if success
        @start()
      else
        console.error "[#{@user_id}] login error"

exports.bid = bid = (commodity_id) ->
  forEachAccount (account) ->
    new Vendue(account).login (success) ->
      @loadChoices (choices) =>
        for choice in choices
          if choice.commodity_id is commodity_id
            @startBidding choice
            @preloadBiddingPage choice, ->
              @.emit 'edge', choice

run()