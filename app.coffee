request = require 'request'
jsontoxml = require 'jsontoxml'
xml2js = require 'xml2js'
iconv = require 'iconv-lite'
{EventEmitter} = require 'events'

Buffer::gbk = ->
  iconv.decode(@, 'gbk')

class Vendue
  
  @tradeweb: 'http://124.127.102.8:16925/tradeweb/'
  @vendue: 'http://124.127.102.18:16910/vendue/'
  @partition_id: 2
  
  constructor: (options) ->
    @user_id = options.user_id
    @password = options.password
    @register_word = options.register_word
    @jar = request.jar()
    
    post = (path, req, json, headers, callback) =>
      console.log "requesting #{path}...\n"
      options =
        encoding: null
        method: 'POST'
        url: path
        jar: @jar
        headers: headers
        body: '<?xml version="1.0" encoding="gb2312"?>' + jsontoxml 
          GNNT:[
            name:'REQ'
            attrs: name: req
            children: json
            ]
      request options, (err, res, body) ->
        body = xml2js.parseString body.gbk(), (err, result) ->
          result = result.GNNT.REP[0].RESULT[0]
          callback? result
    
    @vendue = (path, req, json, callback) ->
      post "#{Vendue.vendue}#{path}", req, json,
        'Content-Type': 'text/xml;charset=GBK'
      , callback
    
    @tradeweb = (path, req, json, callback) ->
      post "#{Vendue.tradeweb}#{path}", req, json,
        'Content-Type': 'text/html'
        'Expect': '100-continue'
      , callback
    
    @get = (path, callback) =>
      request
        encoding: null
        method: 'GET'
        jar: @jar
        url: "#{Vendue.vendue}#{path}"
      , (err, res, body) ->
        callback? body.gbk()
  
  login: (callback) ->
    check_user = (session_id, cb) =>
      @vendue 'login_syn.jsp', 'check_user',
        USER_ID: @user_id
        SESSION_ID: session_id
        MODULE_ID: 2
      , cb
    
    logon = (cb) =>
      console.log @user_id
      @tradeweb 'httpXmlServlet', 'logon',
        USER_ID: @user_id
        PASSWORD: @password
        REGISTER_WORD: @register_word
        VERSIONINFO: '3.0.0.16'
        AUTOLOGIN: 'N'
        MULTICARD: 'Y'
      , cb
    
    logon (res) ->
      session_id = res.RETCODE[0]
      if session_id > 0
        console.log "Session ID: #{session_id}"
        check_user session_id, (res) ->
          callback res.RETCODE[0] is '0'
  
  loadChoices: (callback) ->
    @get 'vendue2_nkst/hq/myChoiceCodeHQ.jsp', (body) ->
      r = /winopen\('(\d+)',\s?'(\w+)'[\s\S]*?<td[\s\S]*?<td[\s\S]*?<td[\s\S]*?>(\d+)[\s\S]*?<td[\s\S]*?<td[\s\S]*?<td[\s\S]*?>(\d+)</g
      choices = []
      while match = r.exec(body)
        choices.push id: match[1], commodity_id: match[2], weight: match[3], count: match[4]
      callback? choices
  
  bid: (choice, cb) ->
    console.log "bidding #{choice.id}, weight: #{choice.weight} ..."
    @get "vendue2_nkst/submit/order.jsp?partitionId=#{Vendue.partition_id}&code=#{choice.id}&commodityId=#{choice.commodity_id}&price=20400.0"
    , (body) =>
      exp = "name=\"(\\S+)\" value=\"#{choice.id}\"\\s*/>" +
      "[\\s\\S]*name=\"(\\S+)\" value=\"#{choice.commodity_id}\"\\s*/>" +
      "[\\s\\S]*name=\"(\\S+)\" value=\"20400.0\"\\s*/>" +
      "[\\s\\S]*name=\"(\\S+)\""
      m = new RegExp(exp).exec(body)
      
      @get "servlet/XMLServlet?reqName=order&partitionId=#{Vendue.partition_id}&commodityId=#{choice.commodityId}"+
      "&#{m[1]}=#{choice.id}&" +
      "#{m[2]}=#{choice.commodity_id}&" +
      "#{m[3]}=20400.0&" +
      "#{m[4]}=#{weight}"
      , (body) ->
        message = /if\(true\){\s*alert\('(.*?)'\)/.exec body
        console.log "#{choice.id}: #{message[1]}"
        cb?(message[1])


class Bidding extends EventEmitter

  constructor: (fn) ->
    @bucket = []
    @.on 'bid', (choice) =>
      @bucket.push choice
      fn choice, (msg) =>
        console.log msg
        @bucket.pop()
        if @bucket.length is 0
          @.emit 'complete'
  
  bid: (choice) ->
    @.emit 'bid', choice
  
  whenDone: (fn) ->
    if @bucket.length
      @.once 'complete', fn
    else
      fn()

vendue = new Vendue
  user_id: 578800
  password: '123'
  register_word: '08ACB5CC227A5882'

bidding = new Bidding(vendue.bid)

vendue.login (success) ->
  if not success
    console.error "login error"
  else
    console.log "logged in"
  
  check = (next) ->
    bidding.whenDone ->
      vendue.loadChoices (choices) ->
        console.log "choices: [#{choices.join(', ')}]"
        if not choices.length
          console.log "no choices, wait 60 seconds..."
          setTimeout next, 60000
        else
          maxCount = 0
          for choice in choices
            maxCount = Math.max(choice.count, maxCount)
            if choice.count is 59
              bidding.bid choice
          if maxCount < 45
            console.log "max count = #{maxCount}, wait 60 seconds..."
            setTimeout next, 60000
          else
            next()
  
  console.log 'checking...'
  checkloop = ->
    check checkloop
  checkloop()
