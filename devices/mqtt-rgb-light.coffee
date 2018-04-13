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
      setWhite:
        description: "set the light to white color"
      setColor:
        description: "set a light color"
        params:
          colorCode:
            type: t.string
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
          if @config.power.stateTopic ==  topic
            switch message.toString()
              when @config.power.onMessage
                @_setAttribute("power", true)
              when @config.power.offMessage
                @_setAttribute("power", false)
              else
                env.logger.debug "#{@name} with id:#{@id}: Message is not harmony with onMessage or offMessage in config.json or with default values"
        )
      
      if @config.color.stateTopic
        @mqttclient.on("message", (topic, message) =>
          if @config.color.stateTopic ==  topic
            message = message.toString()
            @color =  Color(message).rgb()
        )

      super()

    onConnect: () ->
      if @config.power.stateTopic
        @mqttclient.subscribe(@config.power.stateTopic, { qos: @config.qos })
      if @config.color.stateTopic
        @mqttclient.subscribe(@config.color.stateTopic, { qos: @config.qos })

    turnOn: -> 
      if @config.power.topic 
        @mqttclient.publish(@config.power.topic, @config.power.onMessage, { qos: @config.qos, retain: @config.power.retain })
      else 
        message = @_formatColor(@_applyBrightnessOnColor(@color)) #Apply brightness
        @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      _setAttribute("power", true)
      return Promise.resolve()

    turnOff: -> 
      if @config.power.topic 
        @mqttclient.publish(@config.power.topic, @config.power.offMessage, { qos: @config.qos, retain: @config.power.retain })
      else 
        color = Color("#00000")
        message = @_formatColor(color)
        @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      _setAttribute("power", false)
      return Promise.resolve()

    setColor: (newColor) -> 
      newColor = Color(newColor)
      message = @_formatColor(newColor)
      @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      @_setAttribute("color", newColor)
      return Promise.resolve()

    setWhite: -> 
      color = Color("#111111")
      message = @_formatColor(color)
      @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      @_setAttribute("color", color)
      return Promise.resolve()

    setBrightness: (brightnessValue) -> 
      color = @_applyBrightnessOnColor(@color, brightnessValue)
      message = @_formatColor(color)
      @mqttclient.publish(@config.color.topic, message, { qos: @config.qos, retain: @config.color.retain })
      @_setAttribute("brightness", brightnessValue)
      Promise.resolve()

    toggle: ->
      if @power is false then return @turnOn() else return @turnOff()

    getPower: -> Promise.resolve @power
    getColor: -> Promise.resolve @color
    getBrightness: -> Promise.resolve @brightness

    destroy: () ->
      if @config.power.stateTopic
        @mqttclient.unsubscribe(@config.power.stateTopic)
      if @config.color.stateTopic
        @mqttclient.unsubscribe(@config.color.stateTopic)
      super()

    _setAttribute: (attributeName, value) ->
      unless @[attributeName] is value
        @[attributeName] = value
        @emit attributeName, value

    _formatColor: (color) -> 
      return  "#{@color.r},#{color.g},#{color.b}"

    _applyBrightnessOnColor: (color, brightness) ->
      color = _.assign({}, color)
      color.r  = color.r * brightness / 100
      color.g = color.g * brightness / 100
      color.b  = color.b * brightness / 100



