
createRowHeaders = (rowKeys, rowAttrs, colAttrs, tbody, pivotData, aggregatorFunctions, percentAttribute) ->
  for rowKey in rowKeys
    aggregator = pivotData.getAggregator(rowKey, [])
    tr = document.createElement "tr"

    for txt, j in rowKey
      th = document.createElement "th"
      th.className = "pvtRowLabel"
      th.textContent = txt
      th.setAttribute "rowspan", pivotData.valAttrs.length + 1

      if parseInt(j) is rowAttrs.length - 1 and colAttrs.length isnt 0
        th.setAttribute "colspan", 2
      tr.appendChild th

    tbody.appendChild tr

    for attr, index in pivotData.valAttrs
      createValueRow attr, index, rowKey, pivotData, tbody, aggregatorFunctions, percentAttribute, "row"

createValueRow = (attr, index, key, pivotData, tbody, aggregatorFunctions, percentAttribute, type) ->
  tr = document.createElement "tr"
  percentAttrVal = if percentAttribute then aggregatorFunctions.multipleSum([percentAttribute], key, pivotData.filteredInput, type) else null

  if pivotData.opts.table.colTotals or pivotData.rowAttrs.length is 0
    th = document.createElement "th"
    th.className = "pvtTotalLabel pvtColTotalLabel"
    th.innerHTML = attr
    th.setAttribute "colspan", pivotData.rowAttrs.length + (if pivotData.colAttrs.length is 0 then 0 else 1)
    tr.appendChild th

  if pivotData.opts.table.rowTotals or pivotData.colAttrs.length is 0
    td = document.createElement "td"
    td.className = "pvtGrandTotal"
    val = aggregatorFunctions.multipleSum([attr], key, pivotData.filteredInput, type)

    if percentAttrVal and percentAttribute isnt attr
      val = parseFloat(pivotData.getAggregator().format((val / percentAttrVal) * 100))
      td.textContent = pivotData.getAggregator().format(val) + '%'
    else
      td.textContent = pivotData.getAggregator().format(val)

    td.setAttribute "data-value", val
    applyConditionalFormatting td, val, pivotData.inputOperator[index], pivotData.inputThresholds[index]

    tr.appendChild td

  tbody.appendChild tr

applyConditionalFormatting = (td, val, threshOper, inputThresholds) ->
  if threshOper and threshOper.length > 0
    if threshOper.length is 1 and threshOper[0]
      applySingleThreshold td, val, threshOper[0], inputThresholds[0]
    else if threshOper.length is 2
      applyDoubleThreshold td, val, threshOper, inputThresholds

applySingleThreshold = (td, val, oper, threshold) ->
  switch oper
    when '<'
      td.className += " red-highlight" if val < parseFloat(threshold)
    when '='
      td.className += " blue-highlight" if val is parseFloat(threshold)
    when '>'
      td.className += " green-highlight" if val > parseFloat(threshold)

applyDoubleThreshold = (td, val, threshOper, thresholds) ->
  [firstOper, secondOper] = threshOper
  [firstThresh, secondThresh] = thresholds.map parseFloat

  if firstOper and not secondOper
    applySingleThreshold td, val, firstOper, firstThresh
  else if not firstOper and secondOper
    applySingleThreshold td, val, secondOper, secondThresh
  else if firstOper and secondOper
    switch firstOper
      when '<'
        applySecondThreshold td, val, '<', secondOper, firstThresh, secondThresh
      when '='
        applySecondThreshold td, val, '=', secondOper, firstThresh, secondThresh
      when '>'
        applySecondThreshold td, val, '>', secondOper, firstThresh, secondThresh

applySecondThreshold = (td, val, firstOper, secondOper, firstThresh, secondThresh) ->
  switch secondOper
    when '<'
      if (firstOper is '<' and (val < firstThresh or val < secondThresh)) or 
         (firstOper is '=' and (val is firstThresh or val < secondThresh)) or 
         (firstOper is '>' and (val > firstThresh or val < secondThresh))
        td.className += if firstOper is '>' then " green-highlight" else " red-highlight"
    when '='
      if (firstOper is '<' and (val < firstThresh or val is secondThresh)) or 
         (firstOper is '=' and (val is firstThresh or val is secondThresh)) or 
         (firstOper is '>' and (val > firstThresh or val is secondThresh))
        td.className += " blue-highlight"
    when '>'
      if (firstOper is '<' and (val < firstThresh or val > secondThresh)) or 
         (firstOper is '=' and (val is firstThresh or val > secondThresh)) or 
         (firstOper is '>' and (val > firstThresh or val > secondThresh))
        td.className += " green-highlight"

createColumnHeaders = (colKeys, colAttrs, tbody, pivotData, aggregatorFunctions, percentAttribute) ->
  for attr in pivotData.valAttrs
    tr = document.createElement "tr"
    th = document.createElement "th"
    th.className = "pvtTotalLabel pvtColTotalLabel"
    th.innerHTML = attr
    tr.appendChild th

    for colKey in colKeys
      # Add column header creation logic here if needed
