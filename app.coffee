request = require 'request'
request = request.defaults jar:yes
jsontoxml = require 'jsontoxml'
xml2js = require 'xml2js'
iconv = require 'iconv-lite'

Buffer::gbk = ->
  iconv.decode(@, 'gbk')
  
class Vendue
  
  @tradeweb: 'http://124.127.102.8:16925/tradeweb/'
  @vendue: 'http://124.127.102.18:16910/vendue/'
  @user_id: 578800
  @password: '123'
  @register_word: '08ACB5CC227A5882'
  @partition_id: 2
  
  login: (callback) ->
    check_user = (session_id, cb) =>
      @vendue 'login_syn.jsp', 'check_user',
        USER_ID: Vendue.user_id
        SESSION_ID: session_id
        MODULE_ID: 2
      , cb
    
    logon = (cb) =>
      @tradeweb 'httpXmlServlet', 'logon',
        USER_ID: Vendue.user_id
        PASSWORD: Vendue.password
        REGISTER_WORD: Vendue.register_word
        VERSIONINFO: '3.0.0.16'
        AUTOLOGIN: 'N'
        MULTICARD: 'Y'
      , cb
    
    logon (res) ->
      session_id = res.RETCODE[0]
      if session_id > 0
        console.log "Session ID: #{session_id}"
        check_user session_id, (res) ->
          if res.RETCODE[0] is '0'
            console.log 'logged in'
            callback yes
  
  loadChoice: (callback) ->
    @get 'vendue2_nkst/hq/myChoiceCodeHQ.jsp', (body) ->
      r = /winopen\('(\d+)',\s?'(\w+)'/g
      choices = []
      while match = r.exec(body)
        choices.push id: match[1], commodity_id: match[2]
      callback? choices
  
  quotationsAdd: (choices, callback) ->
    body = jsontoxml [
      name: 'REQ'
      attrs: name: 'aqt'
      children:
        P: Vendue.partition_id
        CNT: 350
        ID: (choice.id for choice in choices).join(',')
      ]
    request
      encoding: null
      method: 'POST'
      url: "#{Vendue.vendue}servlet/HTTPXmlServlet?reqName='quotationsAdd'"
      body: body
    , (err, res, body) ->
      body = xml2js.parseString body.gbk(), (err, result) ->
        result = result.MEBS.REP[0]
        callback? result
  
  bid: (choice, weight) ->
    console.log "bidding #{choice.id}, weight: #{weight} ..."
    # @get "vendue2_nkst/submit/order.jsp?partitionId=#{Vendue.partition_id}&code=#{choice.id}&commodityId=#{choice.commodity_id}&price=20400.0"
    # , (body) =>
    @get "servlet/XMLServlet?reqName=order&partitionId=#{Vendue.partition_id}&commodityId=#{choice.commodityId}&ic=#{choice.id}&pdo=#{choice.commodityId}&ibsf=20400.0&zcifx=#{weight}"
    , (body) ->
      message = /if\(true\){\s*alert\('(.*?)'\)/.exec body
      console.log "#{choice.id}: #{message[1]}"
  
  constructor: ->
    post = (path, req, json, headers, callback) =>
      console.log "requesting #{path}...\n"
      options =
        encoding: null
        method: 'POST'
        url: path
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
        url: "#{Vendue.vendue}#{path}"
      , (err, res, body) ->
        callback? body.gbk()

vendue = new Vendue()

vendue.login (ret) ->
  if ret
    vendue.loadChoice (choices) ->
      check = (callback) ->
        vendue.quotationsAdd choices, (body) ->
          if not body.LI
            console.log "closed"
            return
          
          for thread in body.LI[0].HQ
            count = Number(thread.CT[0])
            if count is 59
              id = thread.ID[0]
              weight = Number(thread.YQ[0])
              for choice in choices
                if choice.id is id
                  vendue.bid choice, weight
          callback?()
      
      # loop
      console.log 'checking...'
      checkloop = ->
        check checkloop
      checkloop()
