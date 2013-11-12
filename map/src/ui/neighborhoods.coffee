'use strict'

define [
  'underscore'
  'flight/lib/component',
  'lib/fusiontip/fusiontip',
  'lib/accounting/accounting'
  'map/utils/mobile_detection'
], (
  _,
  defineComponent,
  fusionTip,
  accounting,
  mobileDetection
) ->

  neighborhoodsOverlay = ->

    @defaultAttrs
      enableOnboardCalls: false
      enableMouseover: false
      tableId: undefined
      apiKey: undefined
      hoodLayer: undefined
      gMap: undefined
      toggleLink: undefined
      toggleControl: undefined
      data: undefined
      infoTemplate: undefined
      tipStyle: ''
      mouseTipDelay: 200
      suppressMapTips: false
      minimalZommLevel: 12

      polyOptions:
        clicked:
          strokeColor: "#000"
          strokeOpacity: .5
          strokeWeight: 1
          fillColor: "#000"
          fillOpacity: .2

        mouseover:
          strokeColor: "#000"
          strokeOpacity: .5
          strokeWeight: 1
          fillColor: "#000"
          fillOpacity: .2

        mouseout:
          strokeWeight: 0
          fillOpacity: 0

      polygonOptions:
        fillColor: "BC8F8F"
        fillOpacity: 0.1
        strokeColor: "4D4D4D"
        strokeOpacity: 0.8
        strokeWeight: 1

      polygonOptionsCurrent:
        fillOpacity: 0.5
        strokeColor: '4D4D4D'
        strokeOpacity: 0.7,
        strokeWeight: 2

      infoWindowData:
        state: undefined
        hood: undefined
        population: undefined
        growth: undefined
        density: undefined
        males: undefined
        females: undefined
        median_income: undefined
        average_income: undefined

    @infoWindow = new google.maps.InfoWindow()

    @hoodQuery = (data) ->
      where = "WHERE LATITUDE >= #{data.lat1} AND LATITUDE <= #{data.lat2} AND LONGITUDE >= #{data.lng1} AND LONGITUDE <= #{data.lng2}"
      "SELECT geometry, HOOD_NAME, STATENAME, MARKET FROM #{@attr.tableId} #{where}"


    @addHoodsLayer = (ev, data) ->
      return if !data or !data.gMap or data.gMap.getZoom() < @attr.minimalZommLevel

      @attr.gMap = data.gMap
      @attr.data = data
      @getPolygonData(data)
      @setupMouseOver()

    @setupMouseOver = () ->
      if !@isMobile() && @attr.enableMouseover
        @buildMouseOverWindow()

    @setupLayer = (data) ->
      @getPolygonData(data)

    @getPolygonData = (data) ->
      url = ["https://www.googleapis.com/fusiontables/v1/query?sql="]
      url.push encodeURIComponent(@hoodQuery(data))
      url.push "&key=#{@attr.apiKey}"

      $.ajax
        url: url.join("")
        dataType: "jsonp"
        success: (data) =>
          @buildPolygons(data)


    @buildPolygons = (data) ->
      rows = data.rows
      for i of rows
        continue unless rows[i][0]

        row = @parseRow(rows[i])

        mouseOverOptions = @attr.polyOptions.mouseover
        mouseOutOptions = @attr.polyOptions.mouseout

        hoodLayer = new google.maps.Polygon(
          _.extend({paths:row.paths}, mouseOutOptions)
        )

        google.maps.event.addListener hoodLayer, "mouseover", ->
          @setOptions(mouseOverOptions)


        google.maps.event.addListener hoodLayer, "mouseout", ->
          @setOptions(mouseOutOptions)

        hoodLayer.setMap @attr.gMap

    @parseRow = (row) ->
      hoodData = @parseHoodData(row)
      hoodData.paths = @buildPaths(row)

      hoodData

    @buildPaths = (row) ->
      coordinates = []
      if geometry = row[0].geometry
        if geometry.type == 'Polygon'
          coordinates = @makePaths(geometry.coordinates[0])
      coordinates

    @isPoint = (arr) ->
      arr.length == 2 and _.all(arr, _.isNumber)

    @makePaths = (coordinates) ->
      if this.isPoint(coordinates)
        new google.maps.LatLng(coordinates[1], coordinates[0])
      else
        _.map(coordinates, @makePaths, this)

    @parseHoodData = (row) ->
      if typeof row[0] == 'object'
        _.object(['hood', 'state', 'city'], row.slice(1))
      else
        {}

    @setupToggle = ->
      @positionToggleControl()
      @setupToggleAction()

    @setupToggleAction = ->
      if @attr.toggleLink
        @on @attr.toggleLink, 'click', @toggleLayer

    @positionToggleControl = ->
      if @attr.toggleControl
        control = $('<div/>')
        control.append($(@attr.toggleControl))
        @attr.gMap.controls[google.maps.ControlPosition.TOP_RIGHT].push(control[0])

    @toggleLayer = ->
      if @attr.hoodLayer.getMap()
        @attr.hoodLayer.setMap(null)
      else
        @attr.hoodLayer.setMap(@attr.gMap)
        @setupMouseOver()

    @buildMouseOverWindow = ->
      @attr.hoodLayer.enableMapTips
        select: "HOOD_NAME" # list of columns to query, typially need only one column.
        from: @attr.tableId # fusion table name
        geometryColumn: "geometry" # geometry column name
        suppressMapTips: @attr.suppressMapTips # optional, whether to show map tips. default false
        delay: @attr.mouseTipDelay # milliseconds mouse pause before send a server query. default 300.
        tolerance: 8 # tolerance in pixel around mouse. default is 6.
        key: @attr.apiKey
        style: @attr.tipStyle

    @addListeners = ->
      if @attr.infoTemplate
        google.maps.event.addListener @attr.hoodLayer, 'click', (e) =>
           $(document).trigger 'neighborhoodClicked', { row: e.row, location: e.latLng }

    @buildInfoWindow = (event, data) ->
      @trigger document, 'uiNHoodInfoWindowDataRequest'
      @buildInfoData(event, data)
      event.infoWindowHtml = _.template(@attr.infoTemplate, @attr.infoWindowData)
      @infoWindow.setContent(event.infoWindowHtml)
      @infoWindow.setPosition(data.location)
      @infoWindow.open(@attr.gMap)

    @buildInfoData = (event, data) ->
      row = data.row
      unless _.isEmpty(row)
        @attr.infoWindowData.state = row.STATENAME.value
        @attr.infoWindowData.hood = row.HOOD_NAME.value

        @buildOnboardData(row)

    @buildOnboardData = (row) ->
      return unless @attr.enableOnboardCalls

      data = JSON.parse(@getOnboardData(row).responseText)
      unless _.isEmpty(data)
        demographic = data.demographic
        for key, value of @attr.infoWindowData
          if demographic[key]
            @attr.infoWindowData[key] = @formatValue(key, demographic[key])

    @formatValue = (key, value) ->
      switch key
        when 'median_income', 'average_income'
          accounting.formatMoney(value)
        when 'population'
          accounting.formatNumber(value)
        else
          value

    @getOnboardData = (row) ->
      return {} if _.isEmpty(row)

      query = []
      query.push "state=#{@toDashes(row.STATENAME.value)}"
      query.push "city=#{@toDashes(row.MARKET.value)}"
      query.push "neighborhood=#{@toDashes(row.HOOD_NAME.value)}"

      xhr = $.ajax
        url: "/meta/community?rectype=NH&#{query.join('&')}"
        async: false
      .done (data) ->
        data
      .fail (data) ->
        {}

    @toDashes = (value) ->
      return '' unless value?

      value.replace(' ', '-')

    @toSpaces = (value) ->
      return '' unless value?

      value.replace('-', ' ')

    @after 'initialize', ->
      @on document, 'uiNeighborhoodDataRequest', @addHoodsLayer
      @on document, 'neighborhoodClicked', @buildInfoWindow
      return

  return defineComponent(neighborhoodsOverlay, mobileDetection)

