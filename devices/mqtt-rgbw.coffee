module.exports = (env) ->
  Promise = env.require "bluebird"
  t = env.require("decl-api").types
  _ = env.require("lodash")
  assert = require "cassert"
  Color = require "color"

  class MqttRGBLight extends env.devices.Device
    #getTemplateName: -> "led-light"
    #template: "led-light"

    attributes:
      power:
        description: "the current state of the light"
        type: t.boolean
        labels: ["on", "off"]
      color:
        description: "color of the light"
        type: t.string
        unit: "hex color"
      mode:
        description: "mode of the light"
        type: t.boolean
        labels: ["color", "white"]
      brightness:
       description: "brightness of the light"
       type: t.number
       unit: "%"

    actions:
      getPower:
        description: "returns the current state of the light"
        returns:
          state:
            type: t.boolean
      turnOn:
        description: "turns the light on"
      turnOff:
        description: "turns the light off"
      toggle:
        description: "turns the light on or off"
      setColor:
        description: "set a light color"
        params:
          colorCode:
            type: t.string
      setMode:
        description: "Set mode, white or color"
        params:
          mode:
            type: t.string
            enum: ["color", "white"]
      setBrightness:
        description: "set the light brightness"
        params:
          brightnessValue:
            type: t.string 

    constructor: (@config, @plugin, lastState) ->
      assert(@plugin.brokers[@config.brokerId])

      @mqttclient = @plugin.brokers[@config.brokerId].client

      @name = @config.name
      @id = @config.id

      @power = initState?.power or false
      @color = Color(initState?.color or "#ffff")
      @brightness = initState?.brightness or 100
      @mode = initState?.mode or "color"

      if @mqttclient.connected
        @onConnect()

      @mqttclient.on("connect", =>
        @onConnect()
      )

      if @config.powerStateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.powerStateTopic == topic
            switch message.toString()
              when @config.powerOnMessage
                @turnOn()
              when @config.powerOffMessage
                @turnOff()
              else
                env.logger.debug "#{@name} with id:#{@id}: Message is not harmony with onMessage or offMessage in config.json or with default values"
        )
      
      if @config.colorStateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.colorStateTopic == topic
            message = message.toString()
            color = _parseColor(message)
            color = Color(color).rgb()
            @_setAttribute("color", color)
        )

      if @config.whiteStateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.whiteStateTopic == topic
            message = message.toString()
            brightness = _parseBrightness(message)
            @_setAttribute("brightness", brightness)
        )

      super()

    onConnect: () ->
      if @config.powerStateTopic
        @mqttclient.subscribe(@config.powerStateTopic, { qos: @config.qos })
      if @config.colorStateTopic
        @mqttclient.subscribe(@config.colorStateTopic, { qos: @config.qos })
      if @config.whiteStateTopic
        @mqttclient.subscribe(@config.whiteStateTopic, { qos: @config.qos })

    turnOn: -> 
      if @config.powerTopic 
        @mqttclient.publish(@config.powerTopic, @config.powerOnMessage, { qos: @config.qos, retain: @config.powerRetain })
      else if @mode == "color"
        message = @_formatColor(@color)
        @mqttclient.publish(@config.colorTopic, message, { qos: @config.qos, retain: @config.colorRetain })
      else 
        message = @_formatBrightness(100)
        @mqttclient.publish(@config.whiteTopic, message, { qos: @config.qos, retain: @config.whiteRetain })
      @_setAttribute("power", true)
      return Promise.resolve()

    turnOff: -> 
      if @config.powerTopic 
        @mqttclient.publish(@config.powerTopic, @config.powerOffMessage, { qos: @config.qos, retain: @config.powerRetain })
      else if @mode == "color"
        color = Color("#0000")
        message = @_formatColor(color)
        @mqttclient.publish(@config.colorTopic, message, { qos: @config.qos, retain: @config.colorRetain })
      else 
        message = @_formatBrightness(0) 
        @mqttclient.publish(@config.whiteTopic, message, { qos: @config.qos, retain: @config.whiteRetain })
      @_setAttribute("power", false)
      return Promise.resolve()

    setColor: (newColor) -> 
      newColor = Color(newColor)
      message = @_formatColor(newColor)
      @mqttclient.publish(@config.colorTopic, message, { qos: @config.qos, retain: @config.colorRetain })
      @_setAttribute("color", newColor)
      return Promise.resolve()

    setBrightness: (brightnessValue) -> 
        brightnessValue = parseInt(brightnessValue)
        message = brightnessValue.toString()
        @mqttclient.publish(@config.whiteTopic, message, { qos: @config.qos, retain: @config.whiteRetain })
        @_setAttribute("brightness", brightnessValue)
        Promise.resolve()

    setMode: (mode) -> 
      @_setAttribute("mode", mode)
      if @mode == "color"
        @setColor(@color)
      else
        @setBrightness(@brightness)

    toggle: ->
      if @power is false then return @turnOn() else return @turnOff()

    getPower: -> Promise.resolve @power
    getColor: -> Promise.resolve @color
    getBrightness: -> Promise.resolve @brightness
    getMode: -> Promise.resolve @mode

    destroy: () ->
      if @config.powerStateTopic
        @mqttclient.unsubscribe(@config.powerStateTopic)
      if @config.colorStateTopic
        @mqttclient.unsubscribe(@config.color.stateTopic)
      if @config.whiteStateTopic
        @mqttclient.unsubscribe(@config.whiteStateTopic)
      super()


    _setAttribute: (attributeName, value) ->
      unless @[attributeName] is value
        @[attributeName] = value
        @emit attributeName, value

    _formatBrightness: (brightness) -> # format from config
      return @brightness

    _formatColor: (color) -> 
      return  "#{color.red()},#{color.green()},#{color.blue()}" # format from config

    _parseBrightness: (value) ->
      return parseInt(value)

    _parseColor: (value) ->
      return value