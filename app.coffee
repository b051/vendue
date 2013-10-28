request = require 'request'
jsontoxml = require 'jsontoxml'
xml2js = require 'xml2js'
iconv = require 'iconv-lite'
{EventEmitter} = require 'events'

Buffer::gbk = ->
  iconv.decode(@, 'gbk')

WaitSeconds = 5

class Vendue extends EventEmitter
  
  @tradeweb: 'http://124.127.102.8:16925/tradeweb/'
  @vendue: 'http://124.127.102.17:16911/vendue/'
  @partition_id: 2
  
  constructor: (options) ->
    @user_id = options.user_id
    @password = options.password
    @register_word = options.register_word
    @referer = null
    @jar = request.jar()
    request = request.defaults
      jar: @jar
      # proxy: 'http://10.0.1.8:8888'
      encoding: null
    headers =
      'User-Agent': 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; Trident/4.0)'
      'Accept': "*/*"
      'Accept-Language': 'zh-cn'
      'Accept-Encoding': 'gzip, deflate'
      'x-requeted-with': 'XMLHttpRequest'
    
    @request = (options, fn) ->
      h = options.headers || {}
      for k, v of headers
        h[k] = v
      if @referer
        h['Referer'] = @referer
      options['headers'] = h
      request options, fn
      @bidding = {}
    # 
    # @bucket = []
    # @bidding = {}
    # lock = 0
    # 
    # @.on 'bid', =>
 #      return if lock
 #      choice = @bucket.pop()
 #      return if not choice
 #      
 #      lock = 1
 #      @._bid choice, (msg) =>
 #        lock = 0
 #        if @bucket.length
 #          @.emit 'bid'
  
  @reqXML: (req, json) ->
    '<?xml version="1.0" encoding="gb2312"?>' + jsontoxml 
      GNNT:[
        name:'REQ'
        attrs: name: req
        children: json
        ]
  
  @resXML: (body, callback) ->
    xml2js.parseString body.gbk(), (err, result) ->
      result = result.GNNT.REP[0].RESULT[0]
      callback? result
  
  post: (path, req, json, callback) =>
    @request
      method: 'POST'
      url: "#{Vendue.vendue}#{path}"
      body: Vendue.reqXML(req, json)
    , (err, res, body) ->
      Vendue.resXML body, callback
  
  tradeweb: (path, req, json, callback) ->
    @request
      method: 'POST'
      url: "#{Vendue.tradeweb}#{path}"
      body: Vendue.reqXML(req, json)
    , (err, res, body) ->
      Vendue.resXML body, callback
  
  get: (path, callback) =>
    url = "#{Vendue.vendue}#{path}"
    @request url: url, (err, res, body) ->
      callback? body.gbk()
    @referer = url
  
  login: (callback) ->
    check_user = (session_id, cb) =>
      @post 'login_syn.jsp', 'check_user',
        USER_ID: @user_id
        SESSION_ID: session_id
        MODULE_ID: 2
      , cb
    
    check_user2 = (logon_ip, session_id, cb) =>
      @get "vendue2_nkst/submit/checkuser.jsp?ausessionid=#{session_id}&userid=#{@user_id}&logonip=#{logon_ip}", cb
    
    @tradeweb 'httpXmlServlet', 'logon',
      USER_ID: @user_id
      PASSWORD: @password
      REGISTER_WORD: @register_word
      VERSIONINFO: '3.0.0.16'
      AUTOLOGIN: 'N'
      MULTICARD: 'Y'
    , (res) =>
      session_id = res.RETCODE[0]
      if session_id > 0
        console.log "Session ID: #{session_id}"
        logon_ip = res.LOGONIP[0]
        check_user session_id, (res) =>
          check_user2 logon_ip, session_id
          callback.call @, res.RETCODE[0] is '0'
  
  loadChoices: (callback) ->
    @get 'vendue2_nkst/hq/myChoiceCodeHQ.jsp', (body) ->
      r = /winopen\('(\d+)',\s?'(\w+)'[\s\S]*?<td[\s\S]*?<td[\s\S]*?<td[\s\S]*?>(\d+)[\s\S]*?<td[\s\S]*?<td[\s\S]*?<td[\s\S]*?>(\d+)</g
      choices = []
      while match = r.exec(body)
        choices.push id: match[1], commodity_id: match[2], weight: match[3], count: Number(match[4])
      callback? choices
  
  preloadBiddingPage: (choice) ->
    orderPage = "vendue2_nkst/submit/order.jsp?partitionId=#{Vendue.partition_id}&code=#{choice.id}&commodityId=#{choice.commodity_id}&price=20400.0"
    @referer = null
    
    @get orderPage, (body) =>
      exp = "name=\"(\\S+)\" value=\"#{choice.id}\"\\s*/>" +
      "[\\s\\S]*name=\"(\\S+)\" value=\"#{choice.commodity_id}\"\\s*/>" +
      "[\\s\\S]*name=\"(\\S+)\" value=\"20400.0\"\\s*/>" +
      "[\\s\\S]*name=\"(\\S+)\" value=\"\"\\s*/>"
      m = new RegExp(exp).exec(body)
      return if not m
      orderCommand = "servlet/XMLServlet?reqName=order&partitionId=#{Vendue.partition_id}&commodityId=#{choice.commodity_id}&" +
        "#{m[1]}=#{choice.id}&" +
        "#{m[2]}=#{choice.commodity_id}&" +
        "#{m[3]}=20400.0&" +
        "#{m[4]}=#{choice.weight}"
    
      @bidding[choice.commodity_id] = orderCommand
  
  startBidding: (choice) ->
    @.on 'edge', (_choice) =>
      return if _choice.id isnt choice.id
      url = @bidding[choice.commodity_id]
      return if not url
      @get url, (body) =>
        message = /if\(true\){\s*alert\('(.*?)'\)/.exec body
        console.log "#{choice.commodity_id}: #{message[1]} #{new Date()}"
        @.emit "bid", choice
    
    console.log "bidding #{choice.commodity_id}, weight: #{choice.weight} ..."
  
  check: (next) ->
    @loadChoices (choices) =>
      if not choices.length
        console.log "no choices, wait #{WaitSeconds} seconds..."
        setTimeout next, WaitSeconds * 1000
      else
        maxCount = 0
        avgCount = 0
        for choice in choices
          maxCount = Math.max(choice.count, maxCount)
          avgCount += choice.count
          if choice.count is 59
            @.emit 'edge', choice
        if maxCount < 45
          avgCount = avgCount / choices.length
          console.log "max count = #{maxCount}, average = #{avgCount}, wait #{WaitSeconds} seconds..."
          setTimeout next, WaitSeconds * 1000
        else
          next()
  
  start: ->
    @loadChoices (choices) =>
      reloadBidding = (_choice) =>
        @bidding = {}
        for choice in choices
          if not _choice or _choice.id isnt choice.id
            @preloadBiddingPage choice
      
      @.on 'bid', reloadBidding
      reloadBidding null
      
      choices.forEach (choice) =>
        @startBidding choice
    _loop = =>
      @check _loop
    _loop()


fs = require 'fs'
fs.readFile "accounts.json", (err, content) ->
  accounts = JSON.parse content
  for account in accounts
    continue if not account.enabled
    console.log "starting account #{account.user_id}..."
    
    new Vendue(account).login (success) ->
      if success
        @.start()
      else
        console.error "login error"
