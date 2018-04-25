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
            type: t.number

    constructor: (@config, @plugin, lastState) ->
      assert(@plugin.brokers[@config.brokerId])

      @mqttclient = @plugin.brokers[@config.brokerId].client

      @name = @config.name
      @id = @config.id

      @power = initState?.power or false
      @color = initState?.color or ""
      @brightness = initState?.brightness or 100
      @mode = initState?.mode or "color"

      if @mqttclient.connected
        @onConnect()

      @mqttclient.on("connect", =>
        @onConnect()
      )

      if @config.power.stateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.power.stateTopic == topic
            switch message.toString()
              when @config.power.onMessage
                @turnOn()
              when @config.power.offMessage
                @turnOff()
              else
                env.logger.debug "#{@name} with id:#{@id}: Message is not harmony with onMessage or offMessage in config.json or with default values"
        )
      
      if @config.color.stateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.color.stateTopic == topic
            message = message.toString()
            color = _parseColor(message)
            @_setAttribute("color", Color(color).rgb())
        )

      if @config.white.stateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.white.stateTopic == topic
            message = message.toString()
            brightness = _parseBrightness(message)

            if @mode == "white"
              @_setAttribute("brightness", brightness)
        )

      super()

    onConnect: () ->
      if @config.power.stateTopic
        @mqttclient.subscribe(@config.power.stateTopic, { qos: @config.qos })
      if @config.color.stateTopic
        @mqttclient.subscribe(@config.color.stateTopic, { qos: @config.qos })
      if @config.white.stateTopic
        @mqttclient.subscribe(@config.white.stateTopic, { qos: @config.qos })

    turnOn: -> 
      if @config.power.topic 
        @mqttclient.publish(@config.power.topic, @config.power.onMessage, { qos: @config.qos, retain: @config.power.retain })
      else if @mode == "color"
        message = @_formatColor(@_applyBrightnessOnColor(@color))
        @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      else 
        message = @_formatBrightness(100)
        @mqttclient.publish(@config.white.topic, message, { qos: @config.qos, retain: @config.white.retain })

      _setAttribute("power", true)
      return Promise.resolve()

    turnOff: -> 
      if @config.power.topic 
        @mqttclient.publish(@config.power.topic, @config.power.offMessage, { qos: @config.qos, retain: @config.power.retain })
      else if @mode == "color"
        color = Color("#00000")
        message = @_formatColor(color)
        @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      else 
        message = @_formatBrightness(0) 
        @mqttclient.publish(@config.white.topic, message, { qos: @config.qos, retain: @config.white.retain })

      _setAttribute("power", false)
      return Promise.resolve()

    setColor: (newColor) -> 
      newColor = Color(newColor)
      message = @_formatColor(newColor)
      @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      @_setAttribute("color", newColor)
      return Promise.resolve()

    setBrightness: (brightnessValue) -> 
      if @mode == "color"
        color = @_applyBrightnessOnColor(@color, brightnessValue)
        message = @_formatColor(color)
        @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
        @_setAttribute("color", color)
      else
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
      if @config.power.stateTopic
        @mqttclient.unsubscribe(@config.power.stateTopic)
      if @config.color.stateTopic
        @mqttclient.unsubscribe(@config.color.stateTopic)
      if @config.white.stateTopic
        @mqttclient.unsubscribe(@config.white.stateTopic)
      super()

    _setAttribute: (attributeName, value) ->
      unless @[attributeName] is value
        @[attributeName] = value
        @emit attributeName, value

    _formatBrightness: (brightness) -> # format from config
      return @brightness

    _formatColor: (color) -> 
      return  "#{@color.r},#{color.g},#{color.b}" # format from config

    _parseBrightness: (value) ->
      return parseInt(value)

    _parseColor: (value) ->
      return value

    _applyBrightnessOnColor: (color, brightness) ->
      color = _.assign({}, color)
      color.r  = color.r * brightness / 100
      color.g = color.g * brightness / 100
      color.b  = color.b * brightness / 100


