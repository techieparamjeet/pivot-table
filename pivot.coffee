callWithJQuery = (pivotModule) ->
    if typeof exports is "object" and typeof module is "object" # CommonJS
        pivotModule require("jquery")
    else if typeof define is "function" and define.amd # AMD
        define ["jquery"], pivotModule
    # Plain browser env
    else
        pivotModule jQuery

callWithJQuery ($) ->

    ###
    Utilities
    ###

    addSeparators = (nStr, thousandsSep, decimalSep) ->
        nStr += ''
        x = nStr.split('.')
        x1 = x[0]
        x2 = if x.length > 1 then  decimalSep + x[1] else ''
        rgx = /(\d+)(\d{3})/
        x1 = x1.replace(rgx, '$1' + thousandsSep + '$2') while rgx.test(x1)
        return x1 + x2

    numberFormat = (opts) ->
        defaults =
            digitsAfterDecimal: 2, scaler: 1,
            thousandsSep: ",", decimalSep: "."
            prefix: "", suffix: ""
        opts = $.extend({}, defaults, opts)
        (x) ->
            return "" if isNaN(x) or not isFinite(x)
            if opts.type == 'sum'
                opts.digitsAfterDecimal = if ((x < 0.01 && x > 0)||(x > 99.99 && x < 100)) then 4 else 2
            result = addSeparators (opts.scaler*x).toFixed(opts.digitsAfterDecimal), opts.thousandsSep, opts.decimalSep
            return ""+opts.prefix+result+opts.suffix

    #aggregator templates default to US number formatting but this is overrideable
    usFmt = numberFormat(type: 'sum')
    usFmtInt = numberFormat(digitsAfterDecimal: 0)
    usFmtPct = numberFormat(digitsAfterDecimal:1, scaler: 100, suffix: "%")
    usFmtCustom = numberFormat(digitsAfterDecimal:2, scaler: 100, suffix: "%")
    inputThresholds = [[]]
    inputOperator = [[]]
    percentAttribute = "";
    vennFilteredVariable = [];
    

    aggregatorTemplates =
        count: (formatter=usFmtInt) -> () -> (data, rowKey, colKey) ->
            count: 0
            push:  -> @count++
            value: -> @count
            format: formatter

        uniques: (fn, formatter=usFmtInt) -> ([attr]) -> (data, rowKey, colKey) ->
            uniq: []
            push: (record) -> @uniq.push(record[attr]) if record[attr] not in @uniq
            value: -> fn(@uniq)
            format: formatter
            numInputs: if attr? then 0 else 1

        sum: (formatter=usFmt) -> ([attr]) -> (data, rowKey, colKey) ->
            sum: 0
            push: (record) -> @sum += parseFloat(record[attr]) if not isNaN parseFloat(record[attr])
            value: -> @sum
            format: formatter
            numInputs: if attr? then 0 else 1

        extremes: (mode, formatter=usFmt) -> ([attr]) -> (data, rowKey, colKey) ->
            val: null
            sorter: getSort(data?.sorters, attr)
            push: (record) ->
                x = record[attr]
                if mode in ["min", "max"]
                    x = parseFloat(x)
                    if not isNaN x then @val = Math[mode](x, @val ? x)
                if mode == "first" then @val = x if @sorter(x, @val ? x) <= 0
                if mode == "last"  then @val = x if @sorter(x, @val ? x) >= 0
            value: -> @val
            format: (x) -> if isNaN(x) then x else formatter(x)
            numInputs: if attr? then 0 else 1

        quantile: (q, formatter=usFmt) -> ([attr]) -> (data, rowKey, colKey) ->
            vals: []
            push: (record) ->
                x = parseFloat(record[attr])
                @vals.push(x) if not isNaN(x)
            value: ->
                return null if @vals.length == 0
                @vals.sort((a,b) -> a-b)
                i = (@vals.length-1)*q
                return (@vals[Math.floor(i)] + @vals[Math.ceil(i)])/2.0
            format: formatter
            numInputs: if attr? then 0 else 1

        runningStat: (mode="mean", ddof=1, formatter=usFmt) -> ([attr]) -> (data, rowKey, colKey) ->
            n: 0.0, m: 0.0, s: 0.0
            push: (record) ->
                x = parseFloat(record[attr])
                return if isNaN(x)
                @n += 1.0
                if @n == 1.0
                    @m = x
                else
                    m_new = @m + (x - @m)/@n
                    @s = @s + (x - @m)*(x - m_new)
                    @m = m_new
            value: ->
                if mode == "mean"
                    return if @n == 0 then 0/0 else @m
                return 0 if @n <= ddof
                switch mode
                    when "var"   then @s/(@n-ddof)
                    when "stdev" then Math.sqrt(@s/(@n-ddof))
            format: formatter
            numInputs: if attr? then 0 else 1

        sumOverSum: (formatter=usFmt) -> ([num, denom]) -> (data, rowKey, colKey) ->
            sumNum: 0
            sumDenom: 0
            push: (record) ->
                @sumNum   += parseFloat(record[num])   if not isNaN parseFloat(record[num])
                @sumDenom += parseFloat(record[denom]) if not isNaN parseFloat(record[denom])
            value: -> @sumNum/@sumDenom
            format: formatter
            numInputs: if num? and denom? then 0 else 2

        sumOverSumBound80: (upper=true, formatter=usFmt) -> ([num, denom]) -> (data, rowKey, colKey) ->
            sumNum: 0
            sumDenom: 0
            push: (record) ->
                @sumNum   += parseFloat(record[num])   if not isNaN parseFloat(record[num])
                @sumDenom += parseFloat(record[denom]) if not isNaN parseFloat(record[denom])
            value: ->
                sign = if upper then 1 else -1
                (0.821187207574908/@sumDenom + @sumNum/@sumDenom + 1.2815515655446004*sign*
                    Math.sqrt(0.410593603787454/ (@sumDenom*@sumDenom) + (@sumNum*(1 - @sumNum/ @sumDenom))/ (@sumDenom*@sumDenom)))/
                    (1 + 1.642374415149816/@sumDenom)
            format: formatter
            numInputs: if num? and denom? then 0 else 2

        fractionOf: (wrapped, type="total", formatter=usFmtPct) -> (x...) -> (data, rowKey, colKey) ->
            selector: {total:[[],[]],row:[rowKey,[]],col:[[],colKey]}[type]
            inner: wrapped(x...)(data, rowKey, colKey)
            push: (record) -> @inner.push record
            format: formatter
            value: -> @inner.value() / data.getAggregator(@selector...).inner.value()
            numInputs: wrapped(x...)().numInputs

    aggregatorTemplates.countUnique = (f) -> aggregatorTemplates.uniques(((x) -> x.length), f)
    aggregatorTemplates.listUnique =  (s) -> aggregatorTemplates.uniques(((x) -> x.sort(naturalSort).join(s)), ((x)->x))
    aggregatorTemplates.max =         (f) -> aggregatorTemplates.extremes('max', f)
    aggregatorTemplates.min =         (f) -> aggregatorTemplates.extremes('min', f)
    aggregatorTemplates.first =       (f) -> aggregatorTemplates.extremes('first', f)
    aggregatorTemplates.last =        (f) -> aggregatorTemplates.extremes('last', f)
    aggregatorTemplates.median =      (f) -> aggregatorTemplates.quantile(0.5, f)
    aggregatorTemplates.average =     (f) -> aggregatorTemplates.runningStat("mean", 1, f)
    aggregatorTemplates.var =         (ddof, f) -> aggregatorTemplates.runningStat("var", ddof, f)
    aggregatorTemplates.stdev =       (ddof, f) -> aggregatorTemplates.runningStat("stdev", ddof, f)

    #default aggregators & renderers use US naming and number formatting
    aggregators = do (tpl = aggregatorTemplates) ->
        "Count":                tpl.count(usFmtInt)
        "Count Unique Values":  tpl.countUnique(usFmtInt)
        "List Unique Values":   tpl.listUnique(", ")
        "Sum":                  tpl.sum(usFmt)
        "Integer Sum":          tpl.sum(usFmtInt)
        "Average":              tpl.average(usFmt)
        "Median":               tpl.median(usFmt)
        "Sample Variance":      tpl.var(1, usFmt)
        "Sample Standard Deviation": tpl.stdev(1, usFmt)
        "Minimum":              tpl.min(usFmt)
        "Maximum":              tpl.max(usFmt)
        "First":                tpl.first(usFmt)
        "Last":                 tpl.last(usFmt)
        "Sum over Sum":         tpl.sumOverSum(usFmt)
        "80% Upper Bound":      tpl.sumOverSumBound80(true, usFmt)
        "80% Lower Bound":      tpl.sumOverSumBound80(false, usFmt)
        "Sum as Fraction of Total":     tpl.fractionOf(tpl.sum(),   "total", usFmtPct)
        "Sum as Fraction of Rows":      tpl.fractionOf(tpl.sum(),   "row",   usFmtPct)
        "Sum as Fraction of Columns":   tpl.fractionOf(tpl.sum(),   "col",   usFmtPct)
        "Count as Fraction of Total":   tpl.fractionOf(tpl.count(), "total", usFmtPct)
        "Count as Fraction of Rows":    tpl.fractionOf(tpl.count(), "row",   usFmtPct)
        "Count as Fraction of Columns": tpl.fractionOf(tpl.count(), "col",   usFmtPct)

    renderers =
        "Table":    (data, opts) ->   pivotTableRenderer(data, opts, false)
        "Table (S.No)":   (data, opts) -> serialNumber(data, opts)
        "Table Barchart": (data, opts) -> $(pivotTableRenderer(data, opts, false)).barchart()
        "Heatmap":        (data, opts) -> $(pivotTableRenderer(data, opts, false)).heatmap("heatmap",    opts)
        "Heatmap (Include Totals)":        (data, opts) -> $(pivotTableRenderer(data, opts, false)).heatmap("totalheatmap",    opts)
        "Row Heatmap":    (data, opts) -> $(pivotTableRenderer(data, opts, false)).heatmap("rowheatmap", opts)
        "Col Heatmap":    (data, opts) -> $(pivotTableRenderer(data, opts, false)).heatmap("colheatmap", opts)
        "Table (Display Only)":    (data, opts) -> pivotTableRenderer(data, opts, true)

    locales =
        en:
            aggregators: aggregators
            renderers: renderers
            localeStrings:
                renderError: "An error occurred rendering the PivotTable results."
                computeError: "An error occurred computing the PivotTable results."
                uiRenderError: "An error occurred rendering the PivotTable UI."
                selectAll: "Select All"
                selectNone: "Select None"
                tooMany: "(too many to list)"
                filterResults: "Filter values"
                apply: "Apply"
                cancel: "Cancel"
                totals: "Total" #for table renderer
                vs: "vs" #for gchart renderer
                by: "by" #for gchart renderer

    #dateFormat deriver l10n requires month and day names to be passed in directly
    mthNamesEn = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    dayNamesEn = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
    zeroPad = (number) -> ("0"+number).substr(-2,2)

    derivers =
        bin: (col, binWidth) -> (record) -> record[col] - record[col] % binWidth
        dateFormat: (col, formatString, utcOutput=false, mthNames=mthNamesEn, dayNames=dayNamesEn) ->
            utc = if utcOutput then "UTC" else ""
            (record) -> #thanks http://stackoverflow.com/a/12213072/112871
                date = new Date(Date.parse(record[col]))
                if isNaN(date) then return ""
                formatString.replace /%(.)/g, (m, p) ->
                    switch p
                        when "y" then date["get#{utc}FullYear"]()
                        when "m" then zeroPad(date["get#{utc}Month"]()+1)
                        when "n" then mthNames[date["get#{utc}Month"]()]
                        when "d" then zeroPad(date["get#{utc}Date"]())
                        when "w" then dayNames[date["get#{utc}Day"]()]
                        when "x" then date["get#{utc}Day"]()
                        when "H" then zeroPad(date["get#{utc}Hours"]())
                        when "M" then zeroPad(date["get#{utc}Minutes"]())
                        when "S" then zeroPad(date["get#{utc}Seconds"]())
                        else "%" + p

    rx = /(\d+)|(\D+)/g
    rd = /\d/
    rz = /^0/
    naturalSort = (as, bs) =>
        #nulls first
        return -1 if bs? and not as?
        return  1 if as? and not bs?

        #then raw NaNs
        return -1 if typeof as == "number" and isNaN(as)
        return  1 if typeof bs == "number" and isNaN(bs)

        #numbers and numbery strings group together
        nas = +as
        nbs = +bs
        return -1 if nas < nbs
        return  1 if nas > nbs

        #within that, true numbers before numbery strings
        return -1 if typeof as == "number" and typeof bs != "number"
        return  1 if typeof bs == "number" and typeof as != "number"
        return  0 if typeof as == "number" and typeof bs == "number"

        # 'Infinity' is a textual number, so less than 'A'
        return -1 if isNaN(nbs) and not isNaN(nas)
        return  1 if isNaN(nas) and not isNaN(nbs)

        #finally, "smart" string sorting per http://stackoverflow.com/a/4373421/112871
        a = String(as)
        b = String(bs)
        return 0 if a == b
        return (if a > b then 1 else -1) unless rd.test(a) and rd.test(b)

        #special treatment for strings containing digits
        a = a.match(rx) #create digits vs non-digit chunks and iterate through
        b = b.match(rx)
        while a.length and b.length
            a1 = a.shift()
            b1 = b.shift()
            if a1 != b1
                if rd.test(a1) and rd.test(b1) #both are digit chunks
                    return a1.replace(rz, ".0") - b1.replace(rz, ".0")
                else
                    return (if a1 > b1 then 1 else -1)
        return a.length - b.length

    sortAs = (order) ->
        mapping = {}
        l_mapping = {} # sort lowercased keys similarly
        for i, x of order
            mapping[x] = i
            l_mapping[x.toLowerCase()] = i if typeof x == "string"
        (a, b) ->
            if mapping[a]? and mapping[b]? then mapping[a] - mapping[b]
            else if mapping[a]? then -1
            else if mapping[b]? then 1
            else if l_mapping[a]? and l_mapping[b]? then l_mapping[a] - l_mapping[b]
            else if l_mapping[a]? then -1
            else if l_mapping[b]? then 1
            else naturalSort(a,b)

    getSort = (sorters, attr) ->
        if sorters?
            if $.isFunction(sorters)
                sort = sorters(attr)
                return sort if $.isFunction(sort)
            else if sorters[attr]?
                    if $.isArray(sorters[attr])
                        return sortAs(sorters[attr])
                    else
                        return sorters[attr]
        return naturalSort

    ###
    Data Model class
    ###

    class PivotData
        constructor: (input, opts = {}) ->
            @input = input
            @filteredInput = []
            @aggregator = opts.aggregator ? aggregatorTemplates.count()()
            @aggregatorName = opts.aggregatorName ? "Count"
            @colAttrs = opts.cols ? []
            @rowAttrs = opts.rows ? []
            @valAttrs = opts.vals ? []
            @sorters = opts.sorters ? {}
            @rowOrder = opts.rowOrder ? "key_a_to_z"
            @colOrder = opts.colOrder ? "key_a_to_z"
            @labelOrder = opts.labelOrder ? "key_a_to_z"
            @derivedAttributes = opts.derivedAttributes ? {}
            @filter = opts.filter ? (-> true)
            @tree = {}
            @rowKeys = []
            @colKeys = []
            @rowTotals = {}
            @percentAttribute = percentAttribute ? ""
            @inputThresholds = inputThresholds ? [[]]
            @inputOperator = inputOperator ? [[]]
            @colTotals = {}
            @allTotal = @aggregator(this, [], [])
            @sorted = false

            # iterate through input, accumulating data for cells
            PivotData.forEachRecord @input, @derivedAttributes, (record) =>
                @processRecord(record) if @filter(record)
                @filteredInput.push(record) if @filter(record)
        
        #can handle arrays or jQuery selections of tables
        @forEachRecord = (input, derivedAttributes, f) ->
            if $.isEmptyObject derivedAttributes
                addRecord = f
            else
                addRecord = (record) ->
                    record[k] = v(record) ? record[k] for k, v of derivedAttributes
                    f(record)

            #if it's a function, have it call us back
            if $.isFunction(input)
                input(addRecord)
            else if $.isArray(input)
                if $.isArray(input[0]) #array of arrays
                    for own i, compactRecord of input when i > 0
                        record = {}
                        record[k] = compactRecord[j] for own j, k of input[0]
                        addRecord(record)
                else #array of objects
                    addRecord(record) for record in input
            else if input instanceof $
                tblCols = []
                $("thead > tr > th", input).each (i) -> tblCols.push $(this).text()
                $("tbody > tr", input).each (i) ->
                    record = {}
                    $("td", this).each (j) -> record[tblCols[j]] = $(this).text()
                    addRecord(record)
            else
                throw new Error("unknown input format")

        forEachMatchingRecord: (criteria, callback) ->
            PivotData.forEachRecord @input, @derivedAttributes, (record) =>
                return if not @filter(record)
                for k, v of criteria
                    return if v != (record[k] ? "null")
                callback(record)

        arrSort: (attrs) =>
            sortersArr = (getSort(@sorters, a) for a in attrs)
            (a,b) ->
                for own i, sorter of sortersArr
                    comparison = sorter(a[i], b[i])
                    return comparison if comparison != 0
                return 0

        sortKeys: () =>
            if not @sorted
                @sorted = true
                v = (r,c) => @getAggregator(r,c).value()
                switch @rowOrder
                    when "value_a_to_z"  then @rowKeys.sort (a,b) =>  naturalSort v(a,[]), v(b,[])
                    when "value_z_to_a" then @rowKeys.sort (a,b) => -naturalSort v(a,[]), v(b,[])
                    else             @rowKeys.sort @arrSort(@rowAttrs)
                switch @colOrder
                    when "value_a_to_z"  then @colKeys.sort (a,b) =>  naturalSort v([],a), v([],b)
                    when "value_z_to_a" then @colKeys.sort (a,b) => -naturalSort v([],a), v([],b)
                    else             @colKeys.sort @arrSort(@colAttrs)
                switch @labelOrder
                    when "value_a_to_z"
                        if @valAttrs.length > 1
                            if @colKeys.length > 0 then @valAttrs.sort (a,b) => 
                                naturalSort a, b 
                            else @rowKeys.sort (a,b) =>  
                                naturalSort a[0], b[0]
                        else
                            if @colKeys.length > 0 then @colKeys.sort (a,b) => 
                                naturalSort a, b 
                            else @colKeys.sort (a,b) =>  
                                naturalSort a[0], b[0]
                    when "value_z_to_a"
                        if @valAttrs.length > 1
                            if @colKeys.length > 0 then @valAttrs.sort (a,b) => 
                                -naturalSort a, b 
                            else @rowKeys.sort (a,b) => 
                                -naturalSort a[0], b[0]
                        else
                            if @colKeys.length > 0 then @colKeys.sort (a,b) => 
                                -naturalSort a, b 
                            else @colKeys.sort (a,b) => 
                                -naturalSort a[0], b[0]

        getColKeys: () =>
            @sortKeys()
            return @colKeys

        getRowKeys: () =>
            @sortKeys()
            return @rowKeys

        processRecord: (record) -> #this code is called in a tight loop
            colKey = []
            rowKey = []
            colKey.push record[x] ? "null" for x in @colAttrs
            rowKey.push record[x] ? "null" for x in @rowAttrs
            flatRowKey = rowKey.join(String.fromCharCode(0))
            flatColKey = colKey.join(String.fromCharCode(0))
            @allTotal.push record

            if rowKey.length != 0
                if not @rowTotals[flatRowKey]
                    @rowKeys.push rowKey
                    @rowTotals[flatRowKey] = @aggregator(this, rowKey, [])
                @rowTotals[flatRowKey].push record

            if colKey.length != 0
                if not @colTotals[flatColKey]
                    @colKeys.push colKey
                    @colTotals[flatColKey] = @aggregator(this, [], colKey)
                @colTotals[flatColKey].push record

            if colKey.length != 0 and rowKey.length != 0
                if not @tree[flatRowKey]
                    @tree[flatRowKey] = {}
                if not @tree[flatRowKey][flatColKey]
                    @tree[flatRowKey][flatColKey] = @aggregator(this, rowKey, colKey)
                @tree[flatRowKey][flatColKey].push record
    
        getAggregator: (rowKey, colKey) =>
            flatRowKey = rowKey.join(String.fromCharCode(0))
            flatColKey = colKey.join(String.fromCharCode(0))
            if rowKey.length == 0 and colKey.length == 0
                agg = @allTotal
            else if rowKey.length == 0
                agg = @colTotals[flatColKey]
            else if colKey.length == 0
                agg = @rowTotals[flatRowKey]
            else
                agg = @tree[flatRowKey][flatColKey]
            return agg ? {value: (-> null), format: -> ""}

    #expose these to the outside world
    $.pivotUtilities = {aggregatorTemplates, aggregators, renderers, derivers, locales,
        naturalSort, numberFormat, sortAs, PivotData}

    ###
    Default Renderer for hierarchical table layout
    ###

    pivotTableRenderer = (pivotData, opts, withoutTotal) ->
        defaults =
            table:
                clickCallback: null
                rowTotals: true
                colTotals: true
            localeStrings: totals: "Total"
        
        opts = $.extend(true, {}, defaults, opts)
        colAttrs = pivotData.colAttrs
        rowAttrs = pivotData.rowAttrs
        rowKeys = pivotData.getRowKeys()
        colKeys = pivotData.getColKeys()

        #Sum aggregator #Added by Param
        aggregatorFunctions = 
            multipleSum : (valAttrs, rowKeys, input, type) ->
                sum = 0
                if type == null
                    for val in valAttrs
                        for inp in input
                            sum += parseFloat(inp[val]) if not isNaN parseFloat(inp[val])
                else 
                    attrs = []
                    attrs.push(valAttrs)
                    rowKeys = rowKeys
                    filteredArray = []
                    if type == 'row'
                        keyAttrs = pivotData.rowAttrs
                    else if type == 'col'
                        keyAttrs = pivotData.colAttrs

                    for attr,index in keyAttrs
                            if index==0
                                filteredArray = input.filter (x) -> x[attr] == rowKeys[index]
                            else
                                filteredArray = filteredArray.filter (x) -> x[attr] == rowKeys[index]
                        for arr in filteredArray
                            sum += parseFloat(arr[attrs[0]]) if not isNaN parseFloat(arr[attrs[0]])
                return sum

        if opts.table.clickCallback
            getClickHandler = (value, rowValues, colValues) ->
                filters = {}
                filters[attr] = colValues[i] for own i, attr of colAttrs when colValues[i]?
                filters[attr] = rowValues[i] for own i, attr of rowAttrs when rowValues[i]?
                return (e) -> opts.table.clickCallback(e, value, filters, pivotData)

        #now actually build the output
        result = document.createElement("table")
        result.className = "pvtTable"

        #helper function for setting row/col-span in pivotTableRenderer
        spanSize = (arr, i, j) ->
            if i != 0
                noDraw = true
                for x in [0..j]
                    if arr[i-1][x] != arr[i][x]
                        noDraw = false
                if noDraw
                  return -1 #do not draw cell
            len = 0
            while i+len < arr.length
                stop = false
                for x in [0..j]
                    stop = true if arr[i][x] != arr[i+len][x]
                break if stop
                len++
            return len
        
        multiAttrInputs = ["Sum", "Integer Sum"];
        isMultiple = (multiAttrInputs.indexOf(pivotData.aggregatorName) != -1) && pivotData.valAttrs.length > 1


        #the first few rows are for col headers
        thead = document.createElement("thead")
        for own j, c of colAttrs
            tr = document.createElement("tr")
            if parseInt(j) == 0 and rowAttrs.length != 0
                th = document.createElement("th")
                th.setAttribute("colspan", rowAttrs.length)
                th.setAttribute("rowspan", colAttrs.length)
                tr.appendChild th
            th = document.createElement("th")
            th.className = "pvtAxisLabel"
            th.textContent = c
            tr.appendChild th
            for own i, colKey of colKeys
                x = spanSize(colKeys, parseInt(i), parseInt(j))
                if x != -1
                    th = document.createElement("th")
                    th.className = "pvtColLabel"
                    th.textContent = colKey[j]
                    th.setAttribute("colspan", x)
                    if parseInt(j) == colAttrs.length-1 and rowAttrs.length != 0
                        th.setAttribute("rowspan", 2)
                    tr.appendChild th
            if isMultiple == false
                if parseInt(j) == 0 && opts.table.rowTotals
                    if withoutTotal == false
                        th = document.createElement("th")
                        th.className = "pvtTotalLabel pvtRowTotalLabel"
                        # th.innerHTML = opts.localeStrings.totals -------------- rohan
                        th.innerHTML = "Total"
                        th.setAttribute("rowspan", colAttrs.length + (if rowAttrs.length ==0 then 0 else 1))
                        tr.appendChild th
            thead.appendChild tr

        #then a row for row header headers
        if rowAttrs.length !=0
            tr = document.createElement("tr")
            for own i, r of rowAttrs
                th = document.createElement("th")
                th.className = "pvtAxisLabel"
                th.textContent = r
                tr.appendChild th
            th = document.createElement("th")
            if isMultiple
                th.textContent = "Attribute"
                th.className = "pvtAxisLabel"
                if rowAttrs.length > 1
                    th.setAttribute("colspan",rowAttrs.length)
                tr.appendChild th
            if colAttrs.length != 0
                th = document.createElement("th") #Causing issue
                tr.appendChild th
            if colAttrs.length == 0 && withoutTotal == false
                th.className = "pvtTotalLabel pvtRowTotalLabel"
                # th.innerHTML = opts.localeStrings.totals ------------ rohan
                th.innerHTML = "Total"
                tr.appendChild th
            thead.appendChild tr
        result.appendChild thead

        #now the actual data rows, with their row headers and totals
        
        tbody = document.createElement("tbody")
        #Multiple Aggregator Scenario
        if isMultiple
            if rowKeys.length > 0
                for own i, rowKey of rowKeys
                    aggregator = pivotData.getAggregator(rowKey, [])
                    tr = document.createElement("tr")
                    for own j, txt of rowKey
                        x = pivotData.valAttrs.length
                        if x != -1
                            th = document.createElement("th")
                            th.className = "pvtRowLabel"
                            th.textContent = txt
                            th.setAttribute("rowspan", x+1)
                            if parseInt(j) == rowAttrs.length-1 and colAttrs.length !=0
                                th.setAttribute("colspan",2)
                            tr.appendChild th
                    tbody.appendChild tr
                    for attr,index in pivotData.valAttrs
                        tr = document.createElement("tr")
                        if percentAttribute
                            percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], rowKeys[i] ,pivotData.filteredInput, 'row');
                        if opts.table.colTotals || rowAttrs.length == 0
                            if withoutTotal == false
                                th = document.createElement("th")
                                th.className = "pvtTotalLabel pvtColTotalLabel"
                                th.innerHTML = attr
                                th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 0 else 1))
                                tr.appendChild th
                        if opts.table.rowTotals || colAttrs.length == 0
                            if withoutTotal == false
                                td = document.createElement("td")
                                td.className = "pvtGrandTotal"
                                val = aggregatorFunctions.multipleSum([attr], rowKeys[i] ,pivotData.filteredInput, 'row')
                                if percentAttrVal && percentAttribute != attr
                                    val = parseFloat(aggregator.format((val / percentAttrVal) * 100))
                                    td.textContent = aggregator.format(val) + '%'
                                    if inputOperator.length>0
                                      threshOper = inputOperator[index];
                                      if threshOper && threshOper.length>0
                                        if threshOper.length==1 && threshOper[0]
                                          # 3 cases <,>,=
                                          if threshOper[0] == '<'
                                            if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                              td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0] == '='
                                            if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                              td.className = "pvtGrandTotal blue-highlight"
                                          else if threshOper[0] == '>'
                                            if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                              td.className = "pvtGrandTotal green-highlight"
                                        else if threshOper.length==2
                                          if threshOper[0] && !threshOper[1]
                                            # 3 cases <,>,= paired with ''
                                            if threshOper[0] == '<'
                                              if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal red-highlight"
                                            else if threshOper[0] == '='
                                              if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal blue-highlight"
                                            else if threshOper[0] == '>'
                                              if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal green-highlight"
                                          else if !threshOper[0] && threshOper[1]
                                              # 3 cases <,>,= paired with ''
                                            if threshOper[1] == '<'
                                              if inputThresholds[index] && val < parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal red-highlight"
                                            else if threshOper[1] == '='
                                              if inputThresholds[index] && val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                            else if threshOper[1] == '>'
                                              if inputThresholds[index] && val > parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal green-highlight"
                                          else if threshOper[0] && threshOper[1]
                                              # 7 cases in total < & (<,>,=), > & (<,>,=), = & =
                                              if threshOper[0]=='<' && threshOper[1]=='<' #1
                                                if inputThresholds[index]
                                                  if val < parseFloat(inputThresholds[index][0]) || val < parseFloat(inputThresholds[index][1])
                                                    td.className = "pvtGrandTotal red-highlight"
                                              else if threshOper[0]=='<' && threshOper[1]=='=' #2
                                                if inputThresholds[index]
                                                  if val == parseFloat(inputThresholds[index][1])
                                                    td.className = "pvtGrandTotal blue-highlight"
                                                  else if val < parseFloat(inputThresholds[index][0]) 
                                                    td.className = "pvtGrandTotal red-highlight"
                                              else if threshOper[0]=='<' && threshOper[1]=='>' #3
                                                if inputThresholds[index]
                                                  if val > parseFloat(inputThresholds[index][1])
                                                    td.className = "pvtGrandTotal green-highlight"
                                                  else if val < parseFloat(inputThresholds[index][0]) 
                                                    td.className = "pvtGrandTotal red-highlight"
                                              else if threshOper[0]=='=' && threshOper[1]=='<' #4
                                                if inputThresholds[index]
                                                  if val == parseFloat(inputThresholds[index][0])
                                                    td.className = "pvtGrandTotal blue-highlight"
                                                  else if val < parseFloat(inputThresholds[index][1]) 
                                                    td.className = "pvtGrandTotal red-highlight"
                                              else if threshOper[0]=='=' && threshOper[1]=='=' #5
                                                if inputThresholds[index]
                                                  if val == parseFloat(inputThresholds[index][0]) || val == parseFloat(inputThresholds[index][1])
                                                    td.className = "pvtGrandTotal blue-highlight"
                                              else if threshOper[0]=='=' && threshOper[1]=='>' #6
                                                if inputThresholds[index]
                                                  if val == parseFloat(inputThresholds[index][0])
                                                    td.className = "pvtGrandTotal blue-highlight"
                                                  else if val > parseFloat(inputThresholds[index][1]) 
                                                    td.className = "pvtGrandTotal green-highlight"
                                              else if threshOper[0]=='>' && threshOper[1]=='<' #7
                                                if inputThresholds[index]
                                                  if val > parseFloat(inputThresholds[index][0])
                                                    td.className = "pvtGrandTotal green-highlight"
                                                  else if val < parseFloat(inputThresholds[index][1]) 
                                                    td.className = "pvtGrandTotal red-highlight"
                                              else if threshOper[0]=='>' && threshOper[1]=='=' #8
                                                if inputThresholds[index]
                                                  if val == parseFloat(inputThresholds[index][1])
                                                    td.className = "pvtGrandTotal blue-highlight"
                                                  else if val > parseFloat(inputThresholds[index][0]) 
                                                    td.className = "pvtGrandTotal green-highlight"
                                              else if threshOper[0]=='>' && threshOper[1]=='>' #9
                                                if inputThresholds[index]
                                                  if val > parseFloat(inputThresholds[index][0]) || val > parseFloat(inputThresholds[index][1])
                                                    td.className = "pvtGrandTotal green-highlight"
                                else
                                    td.textContent = aggregator.format(val)
                                td.setAttribute("data-value", val)
                                if getClickHandler?
                                    td.onclick = getClickHandler(val, [], [])
                                tr.appendChild td
                        tbody.appendChild tr
            else if colKeys.length > 0
                for attr,index in pivotData.valAttrs
                    tr = document.createElement("tr")
                    th = document.createElement("th")
                    th.className = "pvtTotalLabel pvtColTotalLabel"
                    th.innerHTML = attr
                    if withoutTotal == false
                        tr.appendChild th
                    for own i, colKey of colKeys
                        if percentAttribute
                            percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], colKeys[i] ,pivotData.filteredInput, 'col');
                        aggregator = pivotData.getAggregator([],colKey)
                        td = document.createElement("td")
                        td.className = "pvtGrandTotal"
                        val = aggregatorFunctions.multipleSum([attr], colKeys[i] ,pivotData.filteredInput, 'col')
                        if percentAttrVal && percentAttribute != attr
                            val = parseFloat(aggregator.format((val / percentAttrVal) * 100))
                            td.textContent = aggregator.format(val) + '%'
                            if inputOperator.length>0
                              threshOper = inputOperator[index];
                              if threshOper && threshOper.length>0
                                if threshOper.length==1 && threshOper[0]
                                  # 3 cases <,>,=
                                  if threshOper[0] == '<'
                                    if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal red-highlight"
                                  else if threshOper[0] == '='
                                    if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal blue-highlight"
                                  else if threshOper[0] == '>'
                                    if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal green-highlight"
                                else if threshOper.length==2
                                  if threshOper[0] && !threshOper[1]
                                    # 3 cases <,>,= paired with ''
                                    if threshOper[0] == '<'
                                      if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                        td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0] == '='
                                      if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                        td.className = "pvtGrandTotal blue-highlight"
                                    else if threshOper[0] == '>'
                                      if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                        td.className = "pvtGrandTotal green-highlight"
                                  else if !threshOper[0] && threshOper[1]
                                      # 3 cases <,>,= paired with ''
                                    if threshOper[1] == '<'
                                      if inputThresholds[index] && val < parseFloat(inputThresholds[index][1])
                                        td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[1] == '='
                                      if inputThresholds[index] && val == parseFloat(inputThresholds[index][1])
                                        td.className = "pvtGrandTotal blue-highlight"
                                    else if threshOper[1] == '>'
                                      if inputThresholds[index] && val > parseFloat(inputThresholds[index][1])
                                        td.className = "pvtGrandTotal green-highlight"
                                  else if threshOper[0] && threshOper[1]
                                      # 7 cases in total < & (<,>,=), > & (<,>,=), = & =
                                      if threshOper[0]=='<' && threshOper[1]=='<' #1
                                        if inputThresholds[index]
                                          if val < parseFloat(inputThresholds[index][0]) || val < parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='<' && threshOper[1]=='=' #2
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val < parseFloat(inputThresholds[index][0]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='<' && threshOper[1]=='>' #3
                                        if inputThresholds[index]
                                          if val > parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal green-highlight"
                                          else if val < parseFloat(inputThresholds[index][0]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='=' && threshOper[1]=='<' #4
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val < parseFloat(inputThresholds[index][1]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='=' && threshOper[1]=='=' #5
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][0]) || val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                      else if threshOper[0]=='=' && threshOper[1]=='>' #6
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val > parseFloat(inputThresholds[index][1]) 
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if threshOper[0]=='>' && threshOper[1]=='<' #7
                                        if inputThresholds[index]
                                          if val > parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal green-highlight"
                                          else if val < parseFloat(inputThresholds[index][1]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='>' && threshOper[1]=='=' #8
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val > parseFloat(inputThresholds[index][0]) 
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if threshOper[0]=='>' && threshOper[1]=='>' #9
                                        if inputThresholds[index]
                                          if val > parseFloat(inputThresholds[index][0]) || val > parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal green-highlight"
                        else
                            td.textContent = aggregator.format(val)
                        if withoutTotal == false
                            tr.appendChild td

                    tbody.appendChild tr
            else
                for attr,index in pivotData.valAttrs
                    totalAggregator = pivotData.getAggregator([], [])
                    tr = document.createElement("tr")
                    if percentAttribute
                        percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], null ,pivotData.filteredInput, null);
                    if opts.table.colTotals || rowAttrs.length == 0
                        if withoutTotal == false
                            th = document.createElement("th")
                            th.className = "pvtTotalLabel pvtColTotalLabel"
                            th.innerHTML = attr
                            th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 0 else 1))
                            tr.appendChild th
                    if opts.table.rowTotals || colAttrs.length == 0
                        if withoutTotal == false
                            td = document.createElement("td")
                            td.className = "pvtGrandTotal"
                            val = aggregatorFunctions.multipleSum([attr], null ,pivotData.filteredInput, null)
                            if percentAttrVal && percentAttribute != attr
                                val = parseFloat(totalAggregator.format((val / percentAttrVal) * 100))
                                td.textContent = totalAggregator.format(val) + '%'
                                if inputOperator.length>0
                                  threshOper = inputOperator[index];
                                  if threshOper && threshOper.length>0
                                    if threshOper.length==1 && threshOper[0]
                                      # 3 cases <,>,=
                                      if threshOper[0] == '<'
                                        if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0] == '='
                                        if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal blue-highlight"
                                      else if threshOper[0] == '>'
                                        if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal green-highlight"
                                    else if threshOper.length==2
                                      if threshOper[0] && !threshOper[1]
                                        # 3 cases <,>,= paired with ''
                                        if threshOper[0] == '<'
                                          if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal red-highlight"
                                        else if threshOper[0] == '='
                                          if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal blue-highlight"
                                        else if threshOper[0] == '>'
                                          if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if !threshOper[0] && threshOper[1]
                                          # 3 cases <,>,= paired with ''
                                        if threshOper[1] == '<'
                                          if inputThresholds[index] && val < parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal red-highlight"
                                        else if threshOper[1] == '='
                                          if inputThresholds[index] && val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                        else if threshOper[1] == '>'
                                          if inputThresholds[index] && val > parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if threshOper[0] && threshOper[1]
                                          # 7 cases in total < & (<,>,=), > & (<,>,=), = & =
                                          if threshOper[0]=='<' && threshOper[1]=='<' #1
                                            if inputThresholds[index]
                                              if val < parseFloat(inputThresholds[index][0]) || val < parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='<' && threshOper[1]=='=' #2
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val < parseFloat(inputThresholds[index][0]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='<' && threshOper[1]=='>' #3
                                            if inputThresholds[index]
                                              if val > parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal green-highlight"
                                              else if val < parseFloat(inputThresholds[index][0]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='=' && threshOper[1]=='<' #4
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val < parseFloat(inputThresholds[index][1]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='=' && threshOper[1]=='=' #5
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][0]) || val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                          else if threshOper[0]=='=' && threshOper[1]=='>' #6
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val > parseFloat(inputThresholds[index][1]) 
                                                td.className = "pvtGrandTotal green-highlight"
                                          else if threshOper[0]=='>' && threshOper[1]=='<' #7
                                            if inputThresholds[index]
                                              if val > parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal green-highlight"
                                              else if val < parseFloat(inputThresholds[index][1]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='>' && threshOper[1]=='=' #8
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val > parseFloat(inputThresholds[index][0]) 
                                                td.className = "pvtGrandTotal green-highlight"
                                          else if threshOper[0]=='>' && threshOper[1]=='>' #9
                                            if inputThresholds[index]
                                              if val > parseFloat(inputThresholds[index][0]) || val > parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal green-highlight"
                            else
                                td.textContent = totalAggregator.format(val)
                            td.setAttribute("data-value", val)
                            if getClickHandler?
                                td.onclick = getClickHandler(val, [], [])
                            tr.appendChild td
                    tbody.appendChild tr 
        
        #Single Aggregator Scenario
        else
            for own i, rowKey of rowKeys
                tr = document.createElement("tr")
                for own j, txt of rowKey
                    x = spanSize(rowKeys, parseInt(i), parseInt(j))
                    if x != -1
                        th = document.createElement("th")
                        th.className = "pvtRowLabel"
                        th.textContent = txt
                        th.setAttribute("rowspan", x)
                        if parseInt(j) == rowAttrs.length-1 and colAttrs.length !=0
                            th.setAttribute("colspan",2)
                        tr.appendChild th
                for own j, colKey of colKeys #this is the tight loop
                    aggregator = pivotData.getAggregator(rowKey, colKey)
                    val = aggregator.value()
                    td = document.createElement("td")
                    td.className = "pvtVal row#{i} col#{j}"
                    td.textContent = aggregator.format(val)
                    td.setAttribute("data-value", val)
                    if getClickHandler?
                        td.onclick = getClickHandler(val, rowKey, colKey)
                    tr.appendChild td

                if opts.table.rowTotals || colAttrs.length == 0
                    if withoutTotal == false
                        totalAggregator = pivotData.getAggregator(rowKey, [])
                        val = totalAggregator.value()
                        td = document.createElement("td")
                        td.className = "pvtTotal rowTotal"
                        td.textContent = totalAggregator.format(val)
                        td.setAttribute("data-value", val)
                        if getClickHandler?
                            td.onclick = getClickHandler(val, rowKey, [])
                        td.setAttribute("data-for", "row"+i)
                        tr.appendChild td
                tbody.appendChild tr

            #finally, the row for col totals, and a grand total
            if opts.table.colTotals || rowAttrs.length == 0
                tr = document.createElement("tr")
                if isMultiple == false
                    if opts.table.colTotals || rowAttrs.length == 0
                        if withoutTotal == false
                            th = document.createElement("th")
                            th.className = "pvtTotalLabel pvtColTotalLabel"
                            # th.innerHTML = opts.localeStrings.totals --------------- rohan
                            th.innerHTML = "Total"
                            th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 0 else 1))
                            tr.appendChild th
                for own j, colKey of colKeys
                    totalAggregator = pivotData.getAggregator([], colKey)
                    val = totalAggregator.value()
                    if withoutTotal == false
                        td = document.createElement("td")
                        td.className = "pvtTotal colTotal"
                        td.textContent = totalAggregator.format(val)
                        td.setAttribute("data-value", val)
                        if getClickHandler?
                            td.onclick = getClickHandler(val, [], colKey)
                        td.setAttribute("data-for", "col"+j)
                        tr.appendChild td
                if opts.table.rowTotals || colAttrs.length == 0
                    if withoutTotal == false
                        totalAggregator = pivotData.getAggregator([], [])
                        val = totalAggregator.value()
                        td = document.createElement("td")
                        td.className = "pvtGrandTotal"
                        td.textContent = totalAggregator.format(val)
                        td.setAttribute("data-value", val)
                        if getClickHandler?
                            td.onclick = getClickHandler(val, [], [])
                        tr.appendChild td
                tbody.appendChild tr
        result.appendChild tbody

        percentAttribute = "";
        
        #squirrel this away for later
        result.setAttribute("data-numrows", rowKeys.length)
        result.setAttribute("data-numcols", colKeys.length)
        
        tableWrapper = document.createElement("div");
        tableWrapper.className = "table-wrapper";
        tableWrapper.setAttribute("data-numrows", rowKeys.length)
        tableWrapper.setAttribute("data-numcols", colKeys.length)

        tableWrapper.append(result)

        return tableWrapper

    ###
    Pivot Table core: create PivotData object and call Renderer on it
    ###

    $.fn.pivot = (input, inputOpts, locale="en") ->
        locale = "en" if not locales[locale]?
        defaults =
            cols : [], rows: [], vals: []
            rowOrder: "key_a_to_z", colOrder: "key_a_to_z", labelOrder: "key_a_to_z"
            dataClass: PivotData
            filter: -> true
            aggregator: aggregatorTemplates.count()()
            aggregatorName: "Count"
            sorters: {}
            derivedAttributes: {}
            renderer: pivotTableRenderer # ---------- rohan renderer
            # renderer: serialNumber

        localeStrings = $.extend(true, {}, locales.en.localeStrings, locales[locale].localeStrings)
        localeDefaults =
            rendererOptions: {localeStrings}
            localeStrings: localeStrings

        opts = $.extend(true, {}, localeDefaults, $.extend({}, defaults, inputOpts))
        result = null
        try
            pivotData = new opts.dataClass(input, opts)
            try
                result = opts.renderer(pivotData, opts.rendererOptions)
            catch e
                console.error(e.stack) if console?
                result = $("<span>").html opts.localeStrings.renderError
        catch e
            console.error(e.stack) if console?
            result = $("<span>").html opts.localeStrings.computeError

        x = this[0]
        x.removeChild(x.lastChild) while x.hasChildNodes()
        return @append result


    ###
    Pivot Table UI: calls Pivot Table core above with options set by user
    ###

    $.fn.pivotUI = (input, inputOpts, overwrite = false, locale="en") ->
        locale = "en" if not locales[locale]?
        defaults =
            derivedAttributes: {}
            aggregators: locales[locale].aggregators
            renderers: locales[locale].renderers
            hiddenAttributes: []
            hiddenFromAggregators: []
            hiddenFromDragDrop: []
            menuLimit: 500
            cols: [], rows: [], vals: []
            rowOrder: "key_a_to_z", colOrder: "key_a_to_z", labelOrder: "key_a_to_z"
            dataClass: PivotData
            exclusions: {}
            inclusions: {}
            unusedAttrsVertical: 85
            autoSortUnusedAttrs: false
            onRefresh: null
            showUI: true
            slicers : []
            slicerValues : []
            singleSelectVariables : []
            inputThresholds : [[]]
            inputOperator : [[]]
            percentCheckbox : false;
            showPercentValues: false;
            percentAttribute : ""
            filter: -> true
            sorters: {}
        
        localeStrings = $.extend(true, {}, locales.en.localeStrings, locales[locale].localeStrings)
        localeDefaults =
            rendererOptions: {localeStrings}
            localeStrings: localeStrings

        existingOpts = @data "pivotUIOptions"
        singleSelectRandomName = Math.floor(Math.random()*1000);

        if not existingOpts? or overwrite
            opts = $.extend(true, {}, localeDefaults, $.extend({}, defaults, inputOpts))
        else
            opts = existingOpts

        try
            #check for grouping object to see if there are any
            #iterates through input and replace the values present in group

            if opts.groupedVariables
                if opts.groupedVariables.length > 0
                    for record in input
                        for val in opts.groupedVariables
                            variableName = val.varName
                            variableGroup = Object.assign({}, val);
                            for group in variableGroup.varGroup
                                groupName = group.groupName
                                for val in group.groupValues
                                    if record[variableName] == val
                                        record[variableName] = groupName;

            # do a first pass on the data to cache a materialized copy of any
            # function-valued inputs and to compute dimension cardinalities

            attrValues = {}
            materializedInput = []
            recordsProcessed = 0
            PivotData.forEachRecord input, opts.derivedAttributes, (record) ->
                return unless opts.filter(record)
                materializedInput.push(record)
                for own attr of record
                    if not attrValues[attr]?
                        attrValues[attr] = {}
                        if recordsProcessed > 0
                            attrValues[attr]["null"] = recordsProcessed
                for attr of attrValues
                    value = record[attr] ? "null"
                    attrValues[attr][value] ?= 0
                    attrValues[attr][value]++
                recordsProcessed++
            
            #start building the output
            uiTable = $("<table>", "class": "pvtUi").attr("cellpadding", 5)
            #renderer control
            rendererControl = $("<td>").addClass("pvtUiCell").addClass("pvtSidebar")

            renderer = $("<select>")
                .addClass('pvtRenderer')
                .appendTo(rendererControl)
                .bind "change", -> 
                    refresh() #capture reference
                    pivotValsWrapper = $(".pvtvals-wrapper .pvtAggregator");
                    # if $(this).val() == "Table (Display Only)"
                    #     pivotValsWrapper.attr('disabled', true);
                    #     $(".pvtvals-wrapper .attr-wrapper").addClass('hidden');
                    #     $(".pvtvals-wrapper .checkbox-wrapper").addClass('hidden');
                    # else
                    #     pivotValsWrapper.attr('disabled', false);
                    #     $(".pvtvals-wrapper .attr-wrapper").removeClass('hidden');
                    #     $(".pvtvals-wrapper .checkbox-wrapper").removeClass('hidden');

                    if $(this).val() == "Venn Diagram"
                        isVennRenderer = $("<div>").addClass("is-venn-renderer").text('For Venn Diagrams, row selection in not required.');
                        $(this).parent().parent().find(".pvtAxisContainer.pvtCols").css("position","relative");
                        $(this).parent().parent().find(".pvtAxisContainer.pvtCols").append(isVennRenderer)
                    else
                        if $(this).parent().parent().find(".is-venn-renderer").length
                            $(this).parent().parent().find(".pvtAxisContainer.pvtCols").css("position","static");
                            $(this).parent().parent().find(".is-venn-renderer").remove()
            for own x of opts.renderers
                $("<option>").val(x).html(x).appendTo(renderer)


            #axis list, including the double-click menu
            unused = $("<td>").attr('title', "List of all variables").addClass('pvtAxisContainer pvtUnused pvtUiCell');
            shownAttributes = (a for a of attrValues when a not in opts.hiddenAttributes)
            shownInAggregators = (c for c in shownAttributes when c not in opts.hiddenFromAggregators)
            shownInDragDrop = (c for c in shownAttributes when c not in opts.hiddenFromDragDrop)


            unusedAttrsVerticalAutoOverride = false
            if opts.unusedAttrsVertical == "auto"
                unusedAttrsVerticalAutoCutoff = 120 # legacy support
            else
                unusedAttrsVerticalAutoCutoff = parseInt opts.unusedAttrsVertical

            if not isNaN(unusedAttrsVerticalAutoCutoff)
                attrLength = 0
                attrLength += a.length for a in shownInDragDrop
                unusedAttrsVerticalAutoOverride = attrLength > unusedAttrsVerticalAutoCutoff

            if opts.unusedAttrsVertical == true or unusedAttrsVerticalAutoOverride
                unused.addClass('pvtVertList')
            else
                unused.addClass('pvtHorizList')

            opts.slicerValues = []
            for val in opts.slicers
                for own i, attr of shownInDragDrop
                    do (attr) ->
                        values = (v for v of attrValues[attr])
                        values.sort(getSort(opts.sorters, attr))
                    
                        if attr == val
                            opts.slicerValues.push(values);
            

            for own i, attr of shownInDragDrop
                do (attr) ->

                    values = (v for v of attrValues[attr])
                    hasExcludedItem = false
                    valueList = $("<div>").addClass('pvtFilterBox').hide()

                    valueList.append $("<h4>").append(
                        $("<span>").text(attr),
                        $("<span>").addClass("count").text("(#{values.length})"),
                        )
                    if values.length > opts.menuLimit
                        valueList.append $("<p>").html(opts.localeStrings.tooMany)
                    else
                        if values.length > 5
                            controls = $("<p>").appendTo(valueList)
                            sorter = getSort(opts.sorters, attr)
                            placeholder = opts.localeStrings.filterResults
                            $("<input>", {type: "text"}).appendTo(controls)
                                .attr({placeholder: placeholder, class: "pvtSearch"})
                                .bind "keyup", ->
                                    filter = $(this).val().toLowerCase().trim()
                                    accept_gen = (prefix, accepted) -> (v) ->
                                        real_filter = filter.substring(prefix.length).trim()
                                        return true if real_filter.length == 0
                                        return Math.sign(sorter(v.toLowerCase(), real_filter)) in accepted
                                    accept =
                                        if      filter.indexOf(">=") == 0 then accept_gen(">=", [1,0])
                                        else if filter.indexOf("<=") == 0 then accept_gen("<=", [-1,0])
                                        else if filter.indexOf(">") == 0  then accept_gen(">",  [1])
                                        else if filter.indexOf("<") == 0  then accept_gen("<",  [-1])
                                        else if filter.indexOf("~") == 0  then (v) ->
                                                return true if filter.substring(1).trim().length == 0
                                                v.toLowerCase().match(filter.substring(1))
                                        else (v) -> v.toLowerCase().indexOf(filter) != -1

                                    valueList.find('.pvtCheckContainer p label span.value').each ->
                                        if accept($(this).text())
                                            $(this).parent().parent().show()
                                        else
                                            $(this).parent().parent().hide()
                            controls.append $("<br>")

                            if opts.singleSelectVariables.indexOf(attr) == -1
                                $("<button>", {type:"button"}).appendTo(controls)
                                    .html(opts.localeStrings.selectAll)
                                    .bind "click", ->
                                        valueList.find("input:visible:not(:checked)")
                                            .prop("checked", true).toggleClass("changed")
                                        return false
                                $("<button>", {type:"button"}).appendTo(controls)
                                    .html(opts.localeStrings.selectNone)
                                    .bind "click", ->
                                        valueList.find("input:visible:checked")
                                            .prop("checked", false).toggleClass("changed")
                                        return false

                        checkContainer = $("<div>").attr('value', attr).addClass("pvtCheckContainer").appendTo(valueList)

                        # sortBy = (key, a, b, r) ->
                        #     r = if r then 1 else -1
                        #     return -1*r if a[key] > b[key]
                        #     return +1*r if a[key] < b[key]
                        #     return 0

                        # sortByMultiple = (a, b, keys) ->
                        #     return r if (r = sortBy key, a, b) for key in keys
                        #     return 0

                        # if attr == opts.trendingVariable
                        #     values.sort (a,b) -> sortByMultiple a, b, [opts.trendingVariable]
                        #     console.log(values);

                        if opts.singleSelectVariables.length > 0
                            for variable in opts.singleSelectVariables
                                if attr == variable
                                    if Object.keys(opts.inclusions).length > 0
                                        if !opts.inclusions.hasOwnProperty(variable)
                                            opts.inclusions[variable] = [values.sort(getSort(opts.sorters, attr))[0]]
                       

                        if attr.toLowerCase() == 'week' && attr == opts.trendingVariable && opts.trendingCriteria == 'lastWeekOfMonth'
                            if opts.pastRun > 0 && (opts.inclusions[attr] == undefined || opts.inclusions[attr] == null || opts.inclusions[attr].length == 0)
                                today = new Date
                                curr_year = today.getFullYear()
                                curr_month_index = today.getMonth()
                                months = [ "Dec", "Nov", "Oct", "Sep", "Aug", "Jul", "Jun", "May", "Apr", "Mar", "Feb", "Jan"];
                                weeks = ["Week 5", "Week 4", "Week 3", "Week 2", "Week 1"]
                                opts.inclusions[attr] = []
                                #if opts.pastRun >= values.length
                                #    opts.inclusions[attr] = values
                                #else
                                count = 0
                                while count < opts.pastRun && curr_year > 2000
                                    mon_i = 0
                                    while mon_i < months.length
                                        week_i = 0
                                        while week_i < weeks.length
                                            full_week_value = curr_year + "." + (12-mon_i) + " (" + months[mon_i] + " " + weeks[week_i] + ")"
                                            if full_week_value in values
                                                if full_week_value not in opts.inclusions[attr]
                                                    opts.inclusions[attr].push(full_week_value)
                                                    count = count + 1
                                                break   
                                            week_i = week_i + 1
                                        mon_i = mon_i + 1
                                    curr_year = curr_year - 1

                        for value in values.sort(getSort(opts.sorters, attr))
                             valueCount = attrValues[attr][value]
                             filterItem = $("<label>")
                             if opts.showUI && opts.enableSort
                                filterItem.append $('<span>').addClass('sort-handle').html('&#9783;')
                             filterItemExcluded = false
                             if opts.inclusions[attr]
                                filterItemExcluded = (value not in opts.inclusions[attr])
                             else if opts.exclusions[attr]
                                filterItemExcluded = (value in opts.exclusions[attr])
                             hasExcludedItem ||= filterItemExcluded
                             if opts.singleSelectVariables.indexOf(attr) == -1
                                $("<input>")
                                    .attr("type", "checkbox").addClass('pvtFilter')
                                    .attr("checked", !filterItemExcluded).data("filter", [attr,value])
                                    .appendTo(filterItem)
                                    .bind "change", -> $(this).toggleClass("changed")
                             else
                                $("<input>")
                                    .attr("type", "radio").addClass('pvtFilter')
                                    .attr("name", singleSelectRandomName + "_" + attr+"-radio") #This name has to be unique for each report in dashboard else will cause issue in reports getting rendered and will be showing blaank report
                                    .attr("checked", !filterItemExcluded).data("filter", [attr,value])
                                    .appendTo(filterItem)
                                    .bind "change", -> $(this).toggleClass("changed")
                             filterItem.append $("<span>").addClass("value").text(value)
                             filterItem.append $("<span>").addClass("count").text("("+valueCount+")")
                             checkContainer.append $("<p>").attr('value', value).append(filterItem)
                        
                        if attr == opts.trendingVariable && opts.trendingCriteria != 'lastWeekOfMonth'
                            if opts.pastRun > 0
                                # if opts.trendingSlicer
                                #     uncheckLength = parseInt(checkContainer.find(".pvtFilter").length) - opts.trendingSlicer
                                # else
                                #     uncheckLength = parseInt(checkContainer.find(".pvtFilter").length) - parseInt(opts.pastRun)
                                
                                uncheckLength = parseInt(checkContainer.find(".pvtFilter").length) - parseInt(opts.pastRun)
                                checkContainer.find(".pvtFilter").each ->
                                    $(this).prop('checked',true);
                                checkContainer.find(".pvtFilter").each ->
                                    if(uncheckLength > 0)
                                        $(this).prop('checked',false);
                                        uncheckLength--;
                                
                                if opts.inclusions[attr]
                                    for val in opts.inclusions[attr]
                                        checkContainer.find(".pvtFilter").each ->
                                            if $(this).siblings(".value")[0].innerText == val
                                                $(this).prop('checked',true);
                                
                                if opts.exclusions[attr]
                                    for val in opts.exclusions[attr]
                                        checkContainer.find(".pvtFilter").each ->
                                            if $(this).siblings(".value")[0].innerText == val
                                                $(this).prop('checked',false);

                    closeFilterBox = ->
                        if valueList.find("[type='checkbox']").length > valueList.find("[type='checkbox']:checked").length || valueList.find("[type='radio']").length > valueList.find("[type='radio']:checked").length
                            attrElem.addClass "pvtFilteredAttribute"
                            vennItemIndex = vennFilteredVariable.indexOf(attr);
                            rowItemIndex = opts.rows.indexOf(attr);
                            if vennItemIndex == -1 && rowItemIndex != -1
                                vennFilteredVariable.push(attr);
                        else
                            attrElem.removeClass "pvtFilteredAttribute"
                            vennItemIndex = vennFilteredVariable.indexOf(attr);
                            rowItemIndex = opts.rows.indexOf(attr);
                            if vennItemIndex != -1
                                vennFilteredVariable.splice(vennItemIndex,1);

                            if rowItemIndex == -1
                                vennFilteredVariable.splice(rowItemIndex,1);

                        valueList.find('.pvtSearch').val('')
                        valueList.find('.pvtCheckContainer p').show()
                        valueList.hide()
                    
                    opts.rendererOptions.venn["vennFilteredVariable"] = vennFilteredVariable
                    finalButtons = $("<p>").appendTo(valueList)

                    if values.length <= opts.menuLimit
                        $("<button>", {type: "button"}).text(opts.localeStrings.apply)
                            .appendTo(finalButtons).bind "click", ->
                                #if valueList.find("[type='checkbox']:checked").length != opts.pastRun
                                #    opts.pastRun = 0;
                                if opts.showUI && opts.enableSort && valueList.find('.pvtCheckContainer p').hasClass('changed')
                                    sliceAttr = valueList.first('h4').find('span').eq(0).text();
                                    preferences = []
                                    valueList.find('.pvtCheckContainer .value').each ->
                                        preferences.push($(this).text())
                                    opts.sorters[sliceAttr] = preferences
                                    valueList.find('.clear-sort-button').show() 
                                if valueList.find(".changed").removeClass("changed").length
                                    refresh()
                                closeFilterBox()

                    $("<button>", {type: "button"}).text(opts.localeStrings.cancel)
                        .appendTo(finalButtons).bind "click", ->
                            valueList.find(".changed:checked")
                                .removeClass("changed").prop("checked", false)
                            valueList.find(".changed:not(:checked)")
                                .removeClass("changed").prop("checked", true)
                            closeFilterBox()

                    #show clear custom sort button
                    if opts.showUI && opts.enableSort
                        $("<button>", {type:"button"}).text('Clear Sort')
                            .appendTo(finalButtons)
                            .css('display', if opts.sorters[attr] then 'inline-block' else 'none')
                            .addClass('clear-sort-button')
                            .bind "click", ->
                                delete opts.sorters[attr]
                                refreshSort(attr)
                                refresh()
                                closeFilterBox()

                    triangleLink = $("<span>").addClass('pvtTriangle')
                        .html(" &#x25BE;").bind "click", (e) ->
                            {left, top} = $(e.currentTarget).position()
                            # left = $(e.currentTarget).offset().left;
                            # top = $(e.currentTarget).offset().top;
                            $(".pvtFilterBox").each ->
                                $(this).hide();
                            valueList.css(left: left+10, top: top+10).show()

                    attrElem = $("<li>").addClass("axis_#{i}")
                        .append $("<span>").addClass('pvtAttr').text(attr).data("attrName", attr).append(triangleLink).bind "dblclick", (e) ->
                            if !$(this).parent().hasClass('disable-sort') 
                                $(this).toggleClass('slicer-attr');
                                value = $(this).clone().children().remove().end().text();
                                if opts.slicers.indexOf(value) == -1
                                    opts.slicers.push(value);
                                    opts.slicerValues.push(values);
                                    #opts.hiddenFromAggregators.push(value);
                                    #opts.shownInAggregators.splice(opts.shownInAggregators.indexOf(value), 1);
                                else
                                    index = opts.slicers.indexOf(value);
                                    opts.slicers.splice(index, 1);
                                    opts.slicerValues.splice(index, 1);
                                    #opts.hiddenFromAggregators.splice(opts.hiddenFromAggregators.indexOf(value), 1);
                                    #opts.shownInAggregators.push(value);
                                #$(".pvtVals select.pvtAttrDropdown").each -> 
                                #    $(this).remove();
                                #refresh()
                                $(".pvtVals select.pvtAttrDropdown option").each -> 
                                    $(this).attr('disabled', opts.slicers.indexOf($(this).val()) >= 0)

                    
                    for val in opts.vals
                        if attr == val
                            attrElem.addClass('disable-sort');
                    
                    if values.length > 1000
                        attrElem.addClass('disable-sort');
                    else
                        attrElem.removeClass('disable-sort');

                    if attr == opts.trendingVariable
                        if opts.pastRun > 0
                            attrElem.addClass('pvtFilteredAttribute')

                    if opts.singleSelectVariables.length > 0
                            for variable in opts.singleSelectVariables
                                if attr == variable
                                    attrElem.addClass('pvtFilteredAttribute')
                    
                    if opts.slicers.length > 0
                        for val in opts.slicers
                            if attr == val
                                attrElem.find('.pvtAttr').addClass('slicer-attr');

                    attrElem.addClass('pvtFilteredAttribute') if hasExcludedItem

                    if hasExcludedItem
                        vennItemIndex = vennFilteredVariable.indexOf(attr);
                        rowItemIndex = opts.rows.indexOf(attr);
                        if vennItemIndex == -1 && rowItemIndex != -1
                            vennFilteredVariable.push(attr);
                    unused.append(attrElem).append(valueList)

                    opts.rendererOptions.venn["vennFilteredVariable"] = vennFilteredVariable

            tr1 = $("<tr>").appendTo(uiTable)
            #aggregator menu and value area

            inputCount = 0;

            aggregator = $("<select>").addClass('pvtAggregator')
                .bind "change", -> 
                    aggregatorValue = $(this).val();
                    if aggregatorValue != 'Sum' && aggregatorValue != 'Integer Sum'
                        opts.inputThresholds = [[]];
                        inputThresholds = [[]];
                        opts.inputOperator = [[]];
                        inputOperator = [[]];
                        # opts.vals = [];
                        opts.percentCheckbox = false;
                        opts.percentAttribute = "";
                        inputCount = 0;
                        $(this).parent().parent().find(".removeAggregator").remove();
                        $(this).parent().parent().find(".attr-wrapper").remove();
                        # $(this).parent().parent().find(".checkbox-wrapper").remove();
                    else
                        if !opts.percentCheckbox #To check if switching from Sum/Integer Sum or any other aggregator
                            $(this).parent().parent().find(".attr-wrapper").remove();
                            $(this).parent().parent().find(".checkbox-wrapper").remove();
                            opts.inputThresholds = [[]];
                            inputThresholds = [[]];
                            opts.inputOperator = [[]];
                            inputOperator = [[]];
                            opts.vals = [];
                    refreshDelayed()
                    $(".pvtAxisContainer .pvtAttr").each ->
                        $(this).parent().removeClass('disable-sort');
            for own x of opts.aggregators
                aggregator.append $("<option>").val(x).html(x)

            ordering =
                key_a_to_z:   {rowSymbol: "&varr;", colSymbol: "&harr;", next: "value_a_to_z"}
                value_a_to_z: {rowSymbol: "&darr;", colSymbol: "&rarr;", next: "value_z_to_a"}
                value_z_to_a: {rowSymbol: "&uarr;", colSymbol: "&larr;", next: "key_a_to_z"}

            rowOrderArrow = $("<a>", role: "button", title: "Row Sort").addClass("pvtRowOrder")
                .data("order", opts.rowOrder).html(ordering[opts.rowOrder].rowSymbol)
                .bind "click", ->
                    $(this).data("order", ordering[$(this).data("order")].next)
                    $(this).html(ordering[$(this).data("order")].rowSymbol)
                    refresh()

            colOrderArrow = $("<a>", role: "button", title: "Column Sort").addClass("pvtColOrder")
                .data("order", opts.colOrder).html(ordering[opts.colOrder].colSymbol)
                .bind "click", ->
                    $(this).data("order", ordering[$(this).data("order")].next)
                    $(this).html(ordering[$(this).data("order")].colSymbol)
                    refresh()
            
            labelOrderArrow = $("<a>", role: "button", title: "Label Sort").addClass("pvtLabelOrder")
                .data("order", opts.labelOrder).html(ordering[opts.labelOrder].colSymbol)
                .bind "click", ->
                    $(this).data("order", ordering[$(this).data("order")].next)
                    $(this).html(ordering[$(this).data("order")].colSymbol)
                    refresh()

            pvtValsTd = $("<td>").addClass('pvtVals pvtUiCell')
            
            wrapperParent = $("<div class='attr-wrapper-parent'>");

            pvtvalsWrapperTd = $("<div class='pvtvals-wrapper'>")
              .append(aggregator)
              .append(rowOrderArrow)
              .append(colOrderArrow)
              .append(labelOrderArrow)
              .append($("<br>"))
            
            pvtvalsWrapperTd.appendTo(pvtValsTd)
            pvtValsTd.appendTo(tr1);

            #column axes
            $("<td>").attr('title', "Row Variables").addClass('pvtAxisContainer pvtHorizList pvtCols pvtUiCell').appendTo(tr1)

            tr2 = $("<tr>").appendTo(uiTable)

            #row axes
            tr2.append $("<td>").attr('title', "Column Variables").addClass('pvtAxisContainer pvtRows pvtUiCell').attr("valign", "top")

            #the actual pivot table container
            pivotTable = $("<td>")
                .attr("valign", "top")
                .addClass('pvtRendererArea')
                .width(opts.rendererOptions.plotly.width)
                .height(opts.rendererOptions.plotly.height)
                .appendTo(tr2)

            #finally the renderer dropdown and unused attribs are inserted at the requested location
            if opts.unusedAttrsVertical == true or unusedAttrsVerticalAutoOverride
                uiTable.find('tr:nth-child(1)').prepend rendererControl
                uiTable.find('tr:nth-child(2)').prepend unused
            else
                uiTable.prepend $("<tr>").append(rendererControl).append(unused)

            #render the UI in its default state
            @html uiTable

            #set up the UI initial state as requested by moving elements around

            for x in opts.cols
                @find(".pvtCols").append @find(".axis_#{$.inArray(x, shownInDragDrop)}")
            for x in opts.rows
                @find(".pvtRows").append @find(".axis_#{$.inArray(x, shownInDragDrop)}")
            if opts.aggregatorName?
                @find(".pvtAggregator").val opts.aggregatorName
            if opts.percentCheckbox?
                @find("#percentCheckbox").val opts.percentCheckbox
            if opts.showPercentValues?
                @find('#showPercentValues').val opts.showPercentValues
            if opts.rendererName?
                @find(".pvtRenderer").val opts.rendererName
                if opts.rendererName == "Venn Diagram"
                    isVennRenderer = $("<div>").addClass("is-venn-renderer").text('For Venn Diagrams, row selection in not required.');
                    $(this).find(".pvtAxisContainer.pvtCols").css("position","relative");
                    $(this).find(".pvtAxisContainer.pvtCols").append(isVennRenderer)
                else
                    if $(this).find(".is-venn-renderer").length
                        $(this).find(".pvtAxisContainer.pvtCols").css("position","static");
                        $(this).find(".is-venn-renderer").remove()


            @find(".pvtUiCell").hide() unless opts.showUI

            initialRender = true
            numberInputs = 1;
            # inputCount = 0;
            if initialRender
                numberInputs = opts.vals.length || 1
                percentAttribute = ""
                

            #set up for refreshing
            refreshDelayed = =>
                subopts =
                    derivedAttributes: opts.derivedAttributes
                    localeStrings: opts.localeStrings
                    rendererOptions: opts.rendererOptions
                    sorters: opts.sorters
                    cols: [], rows: []
                    dataClass: opts.dataClass

                #Added by param, check for multiple aggregators and set numInputs to no of aggregators
                multiAttrInputs = ["Sum", "Integer Sum"];
                inputCount = 0;

                if $.inArray(aggregator.val(), multiAttrInputs) != -1
                    if numberInputs > 0
                        numInputsToProcess = numberInputs
                        if @find(".pvtVals select.pvtAttrDropdown").length == 1 && !initialRender
                            numInputsToProcess = 1
                else
                    numInputsToProcess = opts.aggregators[aggregator.val()]([])().numInputs ? 0
                    numberInputs = 1
                    $(".addAggregator").parent().remove();
                    $(".checkbox-wrapper").remove();
                    $(".threshold-input").each ->
                        $(this).remove();
                    $(".threshold-operator").each ->
                        $(this).remove();
                
                vals = []
                @find(".pvtRows li span.pvtAttr").each -> 
                    attr = $(this).data("attrName");
                    subopts.rows.push(attr)
                @find(".pvtCols li span.pvtAttr").each -> subopts.cols.push $(this).data("attrName")
                @find(".pvtVals .attr-wrapper").each ->
                    if numInputsToProcess == 0
                        $(this).remove()
                @find(".pvtVals select.pvtAttrDropdown").each ->
                    if numInputsToProcess == 0
                        $(this).remove()
                    else
                        numInputsToProcess--
                        vals.push $(this).val() if $(this).val() != ""
              

                rowItemIndex = subopts.rows.indexOf(attr);
                #if numInputsToProcess != 0
                pvtVals = @find(".pvtVals")
                pvtValsWrapper = @find(".pvtvals-wrapper")
                pvtValsCell = @find(".pvtVals.pvtUiCell")

                inputOperator = opts.inputOperator;
                inputThresholds = opts.inputThresholds;
                aggregatorInput = 
                    for aggregatorIndex in [0...numInputsToProcess]
                        inputCount++
                        wrapper = $("<div class='attr-wrapper'>");
                        newDropdown = $("<select>")
                            .addClass('pvtAttrDropdown')
                            .append($("<option>"))
                            .bind "change", ->
                                refresh()
                                refreshSlicers()
                        for attr in shownInAggregators
                            newDropdown.append($("<option>").val(attr).text(attr).attr('disabled', opts.slicers.indexOf(attr) >= 0))

                        wrapper.append(newDropdown)
                        
                        # for default inputs
                        # 1
                        thresholdInput1 = $("<input />", { type: "number", title:"Attribute Threshold", class:"threshold-input hidden input-"+inputCount+"-1", min:"1", max:"99"})
                            .bind "blur", ->
                                localIndex = parseInt($(this).parent().index());
                                if !inputThresholds[(localIndex)]
                                    inputThresholds[localIndex] = [];
                                if !opts.inputThresholds[(localIndex)]
                                    opts.inputThresholds[localIndex] = [];
                                inputThresholds[(localIndex)][0] = $(this).val();
                                opts.inputThresholds[(localIndex)][0] = $(this).val();
                                refresh()
                        thresholdOperator1 = $("<select>", { class:"threshold-operator hidden operator-"+inputCount+"-1"})
                            .bind "change", ->
                                localIndex = parseInt($(this).parent().index())
                                if !inputOperator[(localIndex)]
                                    inputOperator[localIndex] = [];
                                if !opts.inputOperator[(localIndex)]
                                    opts.inputOperator[localIndex] = [];
                                inputOperator[(localIndex)][0] = $(this).val();
                                opts.inputOperator[(localIndex)][0] = $(this).val();
                                refresh()
                        thresholdOperator1.append($("<option>").val('').text(''));
                        thresholdOperator1.append($("<option>").val('>').text('>'));
                        thresholdOperator1.append($("<option>").val('=').text('='));
                        thresholdOperator1.append($("<option>").val('<').text('<'));

                        if opts.inputOperator[aggregatorIndex]
                            thresholdOperator1.val(opts.inputOperator[aggregatorIndex][0]);
                        if opts.inputThresholds[aggregatorIndex]
                            thresholdInput1.val(opts.inputThresholds[aggregatorIndex][0]);

                        # 2
                        thresholdInput2 = $("<input />", { type: "number", title:"Attribute Threshold", class:"threshold-input hidden input-"+inputCount+"-2", min:"1", max:"99"})
                            .bind "blur", ->
                                localIndex = parseInt($(this).parent().index())
                                if !inputThresholds[(localIndex)]
                                    inputThresholds[localIndex] = [];
                                if !opts.inputThresholds[(localIndex)]
                                    opts.inputThresholds[localIndex] = [];
                                inputThresholds[(localIndex)][1] = $(this).val();
                                opts.inputThresholds[(localIndex)][1] = $(this).val();
                                refresh()
                        thresholdOperator2 = $("<select>", { class:"threshold-operator hidden operator-"+inputCount+"-2"})
                            .bind "change", ->
                                localIndex = parseInt($(this).parent().index())
                                if !inputOperator[(localIndex)]
                                    inputOperator[localIndex] = [];
                                if !opts.inputOperator[(localIndex)]
                                    opts.inputOperator[localIndex] = [];
                                inputOperator[(localIndex)][1] = $(this).val();
                                opts.inputOperator[(localIndex)][1] = $(this).val();
                                refresh()
                        thresholdOperator2.append($("<option>").val('').text(''));
                        thresholdOperator2.append($("<option>").val('>').text('>'));
                        thresholdOperator2.append($("<option>").val('=').text('='));
                        thresholdOperator2.append($("<option>").val('<').text('<'));
                        
                        if opts.inputOperator[aggregatorIndex] 
                            thresholdOperator2.val(opts.inputOperator[aggregatorIndex][1]);
                        if opts.inputThresholds[aggregatorIndex]
                            thresholdInput2.val(opts.inputThresholds[aggregatorIndex][1]);
                        
                        if @find("#percentCheckbox").is(':checked')
                            if opts.vals[aggregatorIndex] != opts.percentAttribute
                                thresholdInput1.removeClass('hidden');
                                thresholdOperator1.removeClass('hidden');
                                thresholdInput2.removeClass('hidden');
                                thresholdOperator2.removeClass('hidden');
                            else
                                thresholdInput1.addClass('hidden');
                                thresholdOperator1.addClass('hidden');
                                thresholdInput2.addClass('hidden');
                                thresholdOperator2.addClass('hidden');
                                
                        else 
                            thresholdInput1.addClass('hidden');
                            thresholdOperator1.addClass('hidden');
                            thresholdInput2.addClass('hidden');
                            thresholdOperator2.addClass('hidden');

                        # Remove aggregator functionality
                        removeAggregator = $("<a>", role: "button").addClass("removeAggregator")
                            .html("-")
                            .bind "click", ->
                                numberInputs--
                                inputCount--
                                currElementIndex = parseInt($(this).parent().index();)
                                opts.inputThresholds.splice(currElementIndex, 1);
                                opts.inputOperator.splice(currElementIndex, 1);
                                attrWrapper = $(this).parent();
                                if attrWrapper.siblings('.attr-wrapper').length > 0
                                    attrWrapper.remove()
                                    refresh()

                        
                        if inputCount > 1 && $.inArray(aggregator.val(), multiAttrInputs) != -1
                            wrapper.append(thresholdOperator1);
                            wrapper.append(thresholdInput1)
                            wrapper.append(thresholdOperator2);
                            wrapper.append(thresholdInput2).append(removeAggregator)
                        else
                            wrapper.append(thresholdOperator1);
                            wrapper.append(thresholdInput1)
                            wrapper.append(thresholdOperator2);
                            wrapper.append(thresholdInput2)

                        wrapperParent.append(wrapper);
                pvtValsWrapper.append(wrapperParent);

                #@find(".pvtAxisContainer .pvtAttr").each -> $(this).parent().removeClass('disable-sort');       

                for val in vals
                    @find(".pvtAxisContainer .pvtAttr").each ->
                        value = $(this).clone().children().remove().end().text();
                        if val == value
                            $(this).parent().addClass('disable-sort');
                        else
                            $(this).parent().removeClass('disable-sort');

                $(".pvtAxisContainer").sortable( "destroy" ).sortable
                    update: (e, ui) ->
                        refresh() if not ui.sender?
                    connectWith: @find(".pvtAxisContainer")
                    items: 'li:not(.disable-sort)'
                    placeholder: 'pvtPlaceholder'

                multiAttrInputs = ["Sum", "Integer Sum"];
                if multiAttrInputs.indexOf(aggregator.val()) != -1

                    # Add aggregator functionality
                    addAggregator = $("<a>", role: "button").addClass("addAggregator")
                        .html("+")
                        .bind "click", ->
                            numberInputs++
                            inputCount++
                            wrapper = $("<div class='attr-wrapper'>");
                            wrapper.append(newDropdown = $("<select>")
                                .addClass('pvtAttrDropdown')
                                .append($("<option>"))
                                .bind "change", -> refresh()
                            for attr in shownInAggregators
                                newDropdown.append($("<option>").val(attr).text(attr).attr('disabled', opts.slicers.indexOf(attr) >= 0)));
                            
                            # for add aggregator
                            # 1
                            thresholdInput1 = $("<input />", { type: "number",title:"Attribute Threshold", class:"threshold-input hidden" + " input-"+inputCount+"-1", min:"1", max:"99"})
                                .bind "blur", ->
                                    localIndex = parseInt($(this).parent().index())
                                    if !inputThresholds[(localIndex)]
                                      inputThresholds[localIndex] = [];
                                    if !opts.inputThresholds[(localIndex)]
                                      opts.inputThresholds[localIndex] = [];
                                    inputThresholds[(localIndex)][0] = $(this).val();
                                    opts.inputThresholds[(localIndex)][0] = $(this).val();
                                    refresh()
                            thresholdOperator1 = $("<select>", { class:"threshold-operator operator-"+inputCount+"-1"})
                                .bind "change", ->
                                    localIndex = parseInt($(this).parent().index())
                                    if !inputOperator[(localIndex)]
                                      inputOperator[localIndex] = [];
                                    if !opts.inputOperator[(localIndex)]
                                      opts.inputOperator[localIndex] = [];
                                    inputOperator[(localIndex)][0] = $(this).val();
                                    opts.inputOperator[(localIndex)][0] = $(this).val();
                                    refresh()
                            thresholdOperator1.append($("<option>").val('').text(''));
                            thresholdOperator1.append($("<option>").val('>').text('>'));
                            thresholdOperator1.append($("<option>").val('=').text('='));
                            thresholdOperator1.append($("<option>").val('<').text('<'));
                            # 2
                            thresholdInput2 = $("<input />", { type: "number",title:"Attribute Threshold", class:"threshold-input hidden" + " input-"+inputCount+"-2", min:"1", max:"99"})
                                .bind "blur", ->
                                    localIndex = parseInt($(this).parent().index())
                                    if !inputThresholds[(localIndex)]
                                      inputThresholds[localIndex] = [];
                                    if !opts.inputThresholds[(localIndex)]
                                      opts.inputThresholds[localIndex] = [];
                                    inputThresholds[(localIndex)][1] = $(this).val();
                                    opts.inputThresholds[(localIndex)][1] = $(this).val();
                                    refresh()
                            thresholdOperator2 = $("<select>", { class:"threshold-operator operator-"+inputCount+"-2"})
                                .bind "change", ->
                                    localIndex = parseInt($(this).parent().index())
                                    if !inputOperator[(localIndex)]
                                      inputOperator[localIndex] = [];
                                    if !opts.inputOperator[(localIndex)]
                                      opts.inputOperator[localIndex] = [];
                                    inputOperator[(localIndex)][1] = $(this).val();
                                    opts.inputOperator[(localIndex)][1] = $(this).val();
                                    refresh()
                            thresholdOperator2.append($("<option>").val('').text(''));
                            thresholdOperator2.append($("<option>").val('>').text('>'));
                            thresholdOperator2.append($("<option>").val('=').text('='));
                            thresholdOperator2.append($("<option>").val('<').text('<'));
                            # Remove aggregator functionality
                            removeAggregator = $("<a>", role: "button").addClass("removeAggregator")
                                .html("-")
                                .bind "click", ->
                                    numberInputs--
                                    inputCount--
                                    currElementIndex = parseInt($(this).parent().index();)
                                    # inputThresholds.splice(currElementIndex, 1);
                                    opts.inputThresholds.splice(currElementIndex, 1);
                                    # inputOperator.splice(currElementIndex, 1);
                                    opts.inputOperator.splice(currElementIndex, 1);
                                    attrWrapper = $(this).parent();
                                    if attrWrapper.siblings('.attr-wrapper').length > 0
                                        attrWrapper.remove()
                                        refresh()
                            
                            $(pvtValsCell).animate({ scrollTop: $(pvtValsCell).prop("scrollHeight")}, 1000);
                            # if $(this).parent().parent().parent().find("#percentCheckbox").is(':checked')
                            #     thresholdInput1.removeClass('hidden');
                            #     thresholdOperator1.removeClass('hidden');
                            #     thresholdInput2.removeClass('hidden');
                            #     thresholdOperator2.removeClass('hidden');
                            wrapper.append(thresholdOperator1);
                            wrapper.append(thresholdInput1);
                            wrapper.append(thresholdOperator2);
                            wrapper.append(thresholdInput2).append(removeAggregator);

                            if opts.percentCheckbox
                                thresholdInput1.removeClass('hidden');
                                thresholdOperator1.removeClass('hidden');
                                thresholdInput2.removeClass('hidden');
                                thresholdOperator2.removeClass('hidden');
                            else
                                thresholdInput1.addClass('hidden');
                                thresholdOperator1.addClass('hidden');
                                thresholdInput2.addClass('hidden');
                                thresholdOperator2.addClass('hidden');
                            wrapperParent.append(wrapper);
                    
                    # Sum as percent checkbox
                    checkboxWrapper = $("<div class='checkbox-wrapper'>");

                    percentCheck = $("<input />", { type: "checkbox", id:"percentCheckbox"})
                        .on "click", ->
                            $(this).parent().siblings(".percent-target").val("");
                            $(this).parents(".pvtVals").find(".threshold-input").each ->
                                $(this).addClass('hidden');
                            $(this).parents(".pvtVals").find(".threshold-operator").each ->
                                $(this).addClass('hidden');
                            
                            opts.percentAttribute = "";
                            opts.inputThresholds = [[]];
                            inputThresholds = [[]];
                            opts.inputOperator = [[]];
                            inputOperator = [[]];
                            percentAttribute = "";

                            if $(this).is(':checked')
                                opts.percentCheckbox = true;
                                $(this).parent().siblings(".percent-target").removeClass('hidden');
                                $(this).parent().siblings(".percentValueLabel").removeClass('hidden');
                                $(this).parent().parent().parent().find(".threshold-input").each ->
                                    $(this).removeClass('hidden');
                                    $(this).val("");
                                $(this).parent().parent().parent().find(".threshold-operator").each ->
                                    $(this).removeClass('hidden');
                                    $(this).val("");
                            else
                                opts.percentCheckbox = false;
                                $(this).parent().siblings(".percent-target").addClass('hidden');
                                $(this).parent().siblings(".percentValueLabel").addClass('hidden');
                                $(this).parent().parent().parent().find(".threshold-input").each ->
                                    $(this).addClass('hidden');
                                    $(this).val("");
                                $(this).parent().parent().parent().find(".threshold-operator").each ->
                                    $(this).addClass('hidden');
                                    $(this).val("");
                            refresh()

                    label = $("<label />");
                    percentCheck.appendTo(label);
                    label.append("Sum as Percent of");
                    checkboxWrapper.append(label).append('<br>');

                    newDropdown = $("<select>").addClass('percent-target hidden').append($("<option>"))
                                    .bind "change", ->
                                        opts.percentAttribute = $(this).val();
                                        $(this).parent().siblings(".attr-wrapper").first().children(".pvtAttrDropdown").val(opts.percentAttribute);
                                        refresh()
                    for attr in shownInAggregators
                        newDropdown.append($("<option>").val(attr).text(attr).attr('disabled', opts.slicers.indexOf(attr) >= 0))
                    newDropdown.insertAfter(percentCheck.parent().siblings('br'));

                    percentValueCheck = $("<input />", { type: "checkbox", id:"showPercentValues"})
                        .on "click", ->
                            if $(this).is(':checked')
                                opts.showPercentValues = true;
                            else
                                opts.showPercentValues = false;
                            refresh()
                    percentLabel = $("<label />").addClass('percentValueLabel');
                    percentValueCheck.appendTo(percentLabel);
                    percentLabel.append("Show percent values");
                    # checkboxWrapper.append(percentLabel) //Uncomment this to show checkbox for the percent values along with percent attribute


                    for val in vals
                        @find(".pvtAxisContainer .pvtAttr").each ->
                            value = $(this).clone().children().remove().end().text();
                            if val == value
                                $(this).parent().addClass('disable-sort');

                    $(".pvtAxisContainer").sortable("destroy").sortable
                        update: (e, ui) ->
                            refresh() if not ui.sender?
                        connectWith: @find(".pvtAxisContainer")
                        items: 'li:not(.disable-sort)'
                        placeholder: 'pvtPlaceholder'
                    
                    if @find(".pvtVals .addAggregator").length == 0
                        @find('.pvtVals .attr-wrapper').first().append(addAggregator);
                        checkboxWrapper.insertBefore(@find('.pvtVals .attr-wrapper-parent'));
                            
                    #numInputsToProcess = shownInAggregators.length #Added by Param to repeat for multiple aggregators

                if initialRender
                    vals = opts.vals
                    i = 0
                    @find(".pvtVals select.pvtAttrDropdown").each ->
                        $(this).val vals[i]
                        if i == 0 && vals[i] == opts.percentAttribute
                            $(this).parent().parent().siblings().children('.percentValueLabel').addClass('hidden');
                        i++
                    initialRender = false

                    # disable attrVals on initial render
                    $(".pvtAxisContainer .pvtAttr").each ->
                      attrVal = $(this).clone().children().remove().end().text();
                      if attrVal in opts.vals
                        $(this).parent().addClass('disable-sort');

                subopts.aggregatorName = aggregator.val()
                subopts.vals = vals
                #subopts.rows = vals
                subopts.aggregator = opts.aggregators[aggregator.val()](vals)
                subopts.renderer = opts.renderers[renderer.val()]
                subopts.rowOrder = rowOrderArrow.data("order")
                subopts.colOrder = colOrderArrow.data("order")
                subopts.labelOrder = labelOrderArrow.data("order")
                #construct filter here
                exclusions = {}

                #apply sortable to axis attribute i.e rows, columns
                axisAttributes = subopts.rows.concat(subopts.cols)
                if opts.showUI && opts.enableSort
                    $('.pvtAxisContainer').find('.pvtCheckContainer').each ->
                        attr = $(this).siblings('h4').find('span').eq(0).text()
                        if axisAttributes.indexOf(attr) != -1
                            $(this).find('.sort-handle').show()
                            if $(this).hasClass('ui-sortable')
                                $(this).sortable('destroy')
                            $(this).sortable
                                update: (e, ui) ->
                                    $(ui.item).addClass('changed')
                                connectWith: this
                                items: 'p',
                                cursor: 'move'
                                handle: 'label'
                                placeholder: 'pvtPlaceholder'
                        else
                            $(this).find('.sort-handle').hide()
                            if $(this).hasClass('ui-sortable')
                                $(this).sortable('destroy')
                            if opts.sorters[attr]
                                delete opts.sorters[attr]
                                refreshSort(attr)

                if opts.percentCheckbox
                    @find('#percentCheckbox').prop('checked', true);
                    @find('.percent-target').removeClass('hidden');
                    @find('.threshold-input').each ->
                        $(this).removeClass('hidden');
                    @find('.threshold-operator').each ->
                        $(this).removeClass('hidden');
                else
                    @find('#percentCheckbox').prop('checked', false);
                    @find('.percent-target').addClass('hidden');
                    @find('.threshold-input').each ->
                        $(this).addClass('hidden');
                    @find('.threshold-operator').each ->
                        $(this).addClass('hidden');
                
                if opts.showPercentValues
                    @find('#showPercentValues').prop('checked', true);
                else
                    @find('#showPercentValues').prop('checked', false);
                
                if opts.percentAttribute
                    $(this).find('.percent-target').val(opts.percentAttribute)
                    percentAttribute = opts.percentAttribute;
                
                # if opts.inputThresholds.length > 0
                # if opts.inputThresholds[0] && opts.inputThresholds[0].length!=0 || opts.inputThresholds[1] && opts.inputThresholds[1].length!=0 
                #   $(this).find('.threshold-input').each ->
                #       localIndex1 = parseInt($(this).attr('class').split("input-")[1].split("-")[0])
                #       localIndex2 = parseInt($(this).attr('class').split("input-")[1].split("-")[1])
                #       console.log($(this));
                #       if opts.inputThresholds[(localIndex1 - 1)]
                #         $(this).val(opts.inputThresholds[(localIndex1 - 1)][(localIndex2 - 1)])
                #   inputThresholds = opts.inputThresholds
                # else 
                #   inputThresholds = [[]]
                
                # if opts.inputOperator.length > 0
                # if opts.inputThresholds[0] && opts.inputOperator[0].length!=0 || opts.inputThresholds[1] && opts.inputOperator[1].length!=0
                #   $(this).find('.threshold-operator').each ->
                #       localIndex1 = parseInt($(this).attr('class').split("operator-")[1].split("-")[0])
                #       localIndex2 = parseInt($(this).attr('class').split("operator-")[1].split("-")[1])
                #       console.log($(this));
                #       if opts.inputOperator[(localIndex1 - 1)]
                #         $(this).val(opts.inputOperator[(localIndex1 - 1)][(localIndex2 - 1)])
                #   inputOperator = opts.inputOperator
                # else
                #     inputOperator = [[]]

                @find('input.pvtFilter').not(':checked').each ->
                    filter = $(this).data("filter")
                    if exclusions[filter[0]]?
                        exclusions[filter[0]].push( filter[1] )
                    else
                        exclusions[filter[0]] = [ filter[1] ]
                #include inclusions when exclusions present
                inclusions = {}
                @find('input.pvtFilter:checked').each ->
                    filter = $(this).data("filter")
                    if exclusions[filter[0]]?
                        if inclusions[filter[0]]?
                            inclusions[filter[0]].push( filter[1] )
                        else
                            inclusions[filter[0]] = [ filter[1] ]

                #pvtFilter checkboxes not present if values > menuLimit
                for slic, i in opts.slicers
                    slicerValues = opts.slicerValues[i]
                    if slicerValues.length > opts.menuLimit
                        if slic == opts.trendingVariable
                            inclusions[slic] = if opts.inclusions[slic] then opts.inclusions[slic] else slicerValues.slice(-opts.pastRun)
                            exclusions[slic] = if opts.exclusions[slic] then opts.exclusions[slic] else slicerValues.slice(0, slicerValues.length-opts.pastRun) 
                        else
                            if opts.inclusions[slic]
                                inclusions[slic] = opts.inclusions[slic]
                            if opts.exclusions[slic]
                                exclusions[slic] = opts.exclusions[slic]

                subopts.filter = (record) ->
                    return false if not opts.filter(record)
                    for k,excludedItems of exclusions
                        return false if ""+(record[k] ? 'null') in excludedItems
                    return true
                
                pivotTable.pivot(materializedInput,subopts)
                pivotUIOptions = $.extend {}, opts,
                    cols: subopts.cols
                    rows: subopts.rows
                    colOrder: subopts.colOrder
                    rowOrder: subopts.rowOrder
                    labelOrder: subopts.labelOrder
                    vals: vals
                    exclusions: exclusions
                    inclusions: inclusions
                    inclusionsInfo: inclusions #duplicated for backwards-compatibility
                    aggregatorName: aggregator.val()
                    rendererName: renderer.val()
            
                @data "pivotUIOptions", pivotUIOptions

                pivotUIOptions.percentAttribute = opts.percentAttribute
                pivotUIOptions.inputThresholds = opts.inputThresholds
                pivotUIOptions.inputOperator = opts.inputOperator

                # if requested make sure unused columns are in alphabetical order
                if opts.autoSortUnusedAttrs
                    unusedAttrsContainer = @find("td.pvtUnused.pvtAxisContainer")
                    $(unusedAttrsContainer).children("li")
                        .sort((a, b) => naturalSort($(a).text(), $(b).text()))
                        .appendTo unusedAttrsContainer

                pivotTable.css("opacity", 1)
                opts.onRefresh(pivotUIOptions) if opts.onRefresh?

            refresh = =>
                pivotTable.css("opacity", 0.5)
                setTimeout refreshDelayed, 10
            
            refreshSlicers = =>
                dropdownVals = []
                @find(".pvtVals select.pvtAttrDropdown").each ->
                    dropdownVals.push $(this).val() if $(this).val() != ""
                @find(".pvtAxisContainer .pvtAttr").each -> $(this).parent().removeClass('disable-sort');       
                for val in dropdownVals
                    @find(".pvtAxisContainer .pvtAttr").each ->
                        value = $(this).clone().children().remove().end().text();
                        if val == value
                            $(this).parent().addClass('disable-sort');
                        else
                            $(this).parent().removeClass('disable-sort');

            refreshSort = (attribute) =>
                $('div.pvtCheckContainer[value*="' + attribute + '"]').each ->
                    if $(this).attr('value') == attribute
                        #hide clear sort button
                        if $(this).next('p').find('.clear-sort-button').css('display') == 'inline-block'
                            $(this).next('p').find('.clear-sort-button').css('display', 'none')

                        #clone and reset to default sort
                        cloneContainer = $("<div>")
                        values = Object.keys(attrValues[attribute]).sort(getSort(opts.sorters, attribute))
                        for val in values
                            $(this).children('p').each ->
                                if $(this).attr('value') == val
                                    cloneContainer.append $(this).clone(true)
                        $(this).empty().append cloneContainer.children()

            #the very first refresh will actually display the table
            refresh()

            @find(".pvtAxisContainer").sortable
                    update: (e, ui) -> refresh() if not ui.sender?
                    connectWith: @find(".pvtAxisContainer")
                    items: 'li:not(.disable-sort)'
                    placeholder: 'pvtPlaceholder'
        catch e
            console.error(e.stack) if console?
            @html opts.localeStrings.uiRenderError
        return this

    ###
    Heatmap post-processing
    ###

    $.fn.heatmap = (scope = "heatmap", opts) ->
        numRows = @data "numrows"
        numCols = @data "numcols"

        # given a series of values
        # must return a function to map a given value to a CSS color
        colorScaleGenerator = opts?.heatmap?.colorScaleGenerator
        colorScaleGenerator ?= (values) ->
            min = Math.min(values...)
            max = Math.max(values...)
            return (x) ->
                nonRed = 255 - Math.round 255*(x-min)/(max-min)
                return "rgb(255,#{nonRed},#{nonRed})"

        heatmapper = (scope) =>
            forEachCell = (f) =>
                @find(scope).each ->
                    x = $(this).data("value")
                    f(x, $(this)) if x? and isFinite(x)

            values = []
            forEachCell (x) -> values.push x
            colorScale = colorScaleGenerator(values)
            forEachCell (x, elem) -> elem.css "background-color", colorScale(x)

        switch scope
            when "heatmap" then heatmapper ".pvtVal"
            when "totalheatmap" then heatmapper ".pvtVal"
            when "rowheatmap" then heatmapper ".pvtVal.row#{i}" for i in [0...numRows]
            when "colheatmap" then heatmapper ".pvtVal.col#{j}" for j in [0...numCols]

        if scope != "heatmap"
            heatmapper ".pvtTotal.rowTotal"
            heatmapper ".pvtTotal.colTotal"

        # heatmapper ".pvtTotal.rowTotal"
        # heatmapper ".pvtTotal.colTotal"

        return this

    ###
    Barchart post-processing
    ###

    $.fn.barchart = (opts) ->
        numRows = @data "numrows"
        numCols = @data "numcols"

        barcharter = (scope) =>
            forEachCell = (f) =>
                @find(scope).each ->
                    x = $(this).data("value")
                    f(x, $(this)) if x? and isFinite(x)

            values = []
            forEachCell (x) -> values.push x
            max = Math.max(values...)
            if max < 0
                max = 0
            range = max;
            min = Math.min(values...)
            if min < 0
                range = max - min
            scaler = (x) -> 100*x/(1.4*range)
            forEachCell (x, elem) ->
                text = elem.text()
                wrapper = $("<div>").css
                    "position": "relative"
                    "height": "55px"
                bgColor = "gray"
                bBase = 0
                if min < 0
                    bBase = scaler(-min)
                if x < 0
                    bBase += scaler(x)
                    bgColor = "darkred"
                    x = -x
                wrapper.append $("<div>").css
                    "position": "absolute"
                    "bottom": bBase + "%"
                    "left": 0
                    "right": 0
                    "height": scaler(x) + "%"
                    "background-color": bgColor
                wrapper.append $("<div>").text(text).css
                    "position":"relative"
                    "padding-left":"5px"
                    "padding-right":"5px"

                elem.css("padding": 0,"padding-top": "5px", "text-align": "center").html wrapper

        barcharter ".pvtVal.row#{i}" for i in [0...numRows]
        barcharter ".pvtTotal.colTotal"

        return this

    serialNumber = (pivotData, opts) ->
        defaults =
            table:
                clickCallback: null
                rowTotals: true
                colTotals: true
            localeStrings: totals: "Total"
        
        opts = $.extend(true, {}, defaults, opts)
        colAttrs = pivotData.colAttrs
        rowAttrs = pivotData.rowAttrs
        rowKeys = pivotData.getRowKeys()
        colKeys = pivotData.getColKeys()

        #Sum aggregator #Added by Param
        aggregatorFunctions = 
            multipleSum : (valAttrs, rowKeys, input, type) ->
                sum = 0
                if type == null
                    for val in valAttrs
                        for inp in input
                            sum += parseFloat(inp[val]) if not isNaN parseFloat(inp[val])
                else 
                    attrs = []
                    attrs.push(valAttrs)
                    rowKeys = rowKeys
                    filteredArray = []
                    if type == 'row'
                        keyAttrs = pivotData.rowAttrs
                    else if type == 'col'
                        keyAttrs = pivotData.colAttrs

                    for attr,index in keyAttrs
                            if index==0
                                filteredArray = input.filter (x) -> x[attr] == rowKeys[index]
                            else
                                filteredArray = filteredArray.filter (x) -> x[attr] == rowKeys[index]
                        for arr in filteredArray
                            sum += parseFloat(arr[attrs[0]]) if not isNaN parseFloat(arr[attrs[0]])
                return sum

        if opts.table.clickCallback
            getClickHandler = (value, rowValues, colValues) ->
                filters = {}
                filters[attr] = colValues[i] for own i, attr of colAttrs when colValues[i]?
                filters[attr] = rowValues[i] for own i, attr of rowAttrs when rowValues[i]?
                return (e) -> opts.table.clickCallback(e, value, filters, pivotData)

        #now actually build the output
        result = document.createElement("table")
        result.className = "pvtTable"

        #helper function for setting row/col-span in pivotTableRenderer
        spanSize = (arr, i, j) ->
            if i != 0
                noDraw = true
                for x in [0..j]
                    if arr[i-1][x] != arr[i][x]
                        noDraw = false
                if noDraw
                  return -1 #do not draw cell
            len = 0
            while i+len < arr.length
                stop = false
                for x in [0..j]
                    stop = true if arr[i][x] != arr[i+len][x]
                break if stop
                len++
            return len
        
        multiAttrInputs = ["Sum", "Integer Sum"];
        isMultiple = (multiAttrInputs.indexOf(pivotData.aggregatorName) != -1) && pivotData.valAttrs.length > 0


        #the first few rows are for col headers
        thead = document.createElement("thead")

        # S.No --------------------------- rohan
        tr = document.createElement("tr")
        th = document.createElement("th")
        th.innerHTML = "S.No"
        th.setAttribute("rowspan", 0)
        tr.appendChild th
        thead.appendChild tr
        # --------------------------------

        for own j, c of colAttrs
            tr = document.createElement("tr")
            if parseInt(j) == 0 and rowAttrs.length != 0
                th = document.createElement("th")
                th.setAttribute("colspan", rowAttrs.length)
                th.setAttribute("rowspan", colAttrs.length)
                tr.appendChild th
            th = document.createElement("th")
            th.className = "pvtAxisLabel"
            th.textContent = c
            tr.appendChild th
            for own i, colKey of colKeys
                x = spanSize(colKeys, parseInt(i), parseInt(j))
                if x != -1
                    th = document.createElement("th")
                    th.className = "pvtColLabel"
                    th.textContent = colKey[j]
                    th.setAttribute("colspan", x)
                    if parseInt(j) == colAttrs.length-1 and rowAttrs.length != 0
                        th.setAttribute("rowspan", 2)
                    tr.appendChild th
            # To hide spanned column total box --------------------------------------------- rohan
            totalAggregator = pivotData.getAggregator([], [])
            valSpannedTotal = totalAggregator.value()
            # console.log "hiding spanned column total box when value is: "+val
            if typeof valSpannedTotal != "string"
                if isMultiple == false
                    if parseInt(j) == 0 && opts.table.rowTotals
                        th = document.createElement("th")
                        th.className = "pvtTotalLabel pvtRowTotalLabel"
                        # th.innerHTML = opts.localeStrings.totals -------------- rohan
                        th.innerHTML = "Total"
                        th.setAttribute("rowspan", colAttrs.length + (if rowAttrs.length ==0 then 0 else 1))
                        tr.appendChild th
            thead.appendChild tr

        #then a row for row header headers
        if rowAttrs.length !=0
            tr = document.createElement("tr")
            for own i, r of rowAttrs
                th = document.createElement("th")
                th.className = "pvtAxisLabel"
                th.textContent = r
                tr.appendChild th
            th = document.createElement("th")
            if isMultiple
                th.textContent = "Attribute"
                th.className = "pvtAxisLabel"
                if rowAttrs.length > 1
                    th.setAttribute("colspan",rowAttrs.length)
                tr.appendChild th
            # To hide non-spanned column total box --------------------------------------------- rohan
            totalAggregator = pivotData.getAggregator([], [])
            valNonSpannedTotal = totalAggregator.value()
            # console.log "hiding non-spanned column total box when value is: "+val
            if typeof valNonSpannedTotal != "string"
                th = document.createElement("th")
                if colAttrs.length ==0
                    th.className = "pvtTotalLabel pvtRowTotalLabel"
                    # th.innerHTML = opts.localeStrings.totals --------------- rohan
                    th.innerHTML = "Total"
                tr.appendChild th
            thead.appendChild tr
        result.appendChild thead

        #now the actual data rows, with their row headers and totals
        
        tbody = document.createElement("tbody")
        #Multiple Aggregator Scenario
        if isMultiple
            if rowKeys.length > 0
                for own i, rowKey of rowKeys
                    aggregator = pivotData.getAggregator(rowKey, [])
                    tr = document.createElement("tr")
                    for own j, txt of rowKey
                        x = pivotData.valAttrs.length
                        if x != -1
                            th = document.createElement("th")
                            th.className = "pvtRowLabel"
                            th.textContent = txt
                            th.setAttribute("rowspan", x+1)
                            if parseInt(j) == rowAttrs.length-1 and colAttrs.length !=0
                                th.setAttribute("colspan",2)
                            tr.appendChild th
                    tbody.appendChild tr
                    for attr,index in pivotData.valAttrs
                        tr = document.createElement("tr")
                        if percentAttribute
                            percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], rowKeys[i] ,pivotData.filteredInput, 'row');
                        if opts.table.colTotals || rowAttrs.length == 0
                            th = document.createElement("th")
                            th.className = "pvtTotalLabel pvtColTotalLabel"
                            th.innerHTML = attr
                            th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 0 else 1))
                            tr.appendChild th
                        if opts.table.rowTotals || colAttrs.length == 0
                            td = document.createElement("td")
                            td.className = "pvtGrandTotal"
                            val = aggregatorFunctions.multipleSum([attr], rowKeys[i] ,pivotData.filteredInput, 'row')
                            if percentAttrVal && percentAttribute != attr
                                val = parseFloat(aggregator.format((val / percentAttrVal) * 100))
                                td.textContent = aggregator.format(val) + '%'
                                if inputOperator.length>0
                                  threshOper = inputOperator[index];
                                  if threshOper && threshOper.length>0
                                    if threshOper.length==1 && threshOper[0]
                                      # 3 cases <,>,=
                                      if threshOper[0] == '<'
                                        if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0] == '='
                                        if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal blue-highlight"
                                      else if threshOper[0] == '>'
                                        if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal green-highlight"
                                    else if threshOper.length==2
                                      if threshOper[0] && !threshOper[1]
                                        # 3 cases <,>,= paired with ''
                                        if threshOper[0] == '<'
                                          if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal red-highlight"
                                        else if threshOper[0] == '='
                                          if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal blue-highlight"
                                        else if threshOper[0] == '>'
                                          if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if !threshOper[0] && threshOper[1]
                                          # 3 cases <,>,= paired with ''
                                        if threshOper[1] == '<'
                                          if inputThresholds[index] && val < parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal red-highlight"
                                        else if threshOper[1] == '='
                                          if inputThresholds[index] && val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                        else if threshOper[1] == '>'
                                          if inputThresholds[index] && val > parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if threshOper[0] && threshOper[1]
                                          # 7 cases in total < & (<,>,=), > & (<,>,=), = & =
                                          if threshOper[0]=='<' && threshOper[1]=='<' #1
                                            if inputThresholds[index]
                                              if val < parseFloat(inputThresholds[index][0]) || val < parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='<' && threshOper[1]=='=' #2
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val < parseFloat(inputThresholds[index][0]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='<' && threshOper[1]=='>' #3
                                            if inputThresholds[index]
                                              if val > parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal green-highlight"
                                              else if val < parseFloat(inputThresholds[index][0]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='=' && threshOper[1]=='<' #4
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val < parseFloat(inputThresholds[index][1]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='=' && threshOper[1]=='=' #5
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][0]) || val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                          else if threshOper[0]=='=' && threshOper[1]=='>' #6
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val > parseFloat(inputThresholds[index][1]) 
                                                td.className = "pvtGrandTotal green-highlight"
                                          else if threshOper[0]=='>' && threshOper[1]=='<' #7
                                            if inputThresholds[index]
                                              if val > parseFloat(inputThresholds[index][0])
                                                td.className = "pvtGrandTotal green-highlight"
                                              else if val < parseFloat(inputThresholds[index][1]) 
                                                td.className = "pvtGrandTotal red-highlight"
                                          else if threshOper[0]=='>' && threshOper[1]=='=' #8
                                            if inputThresholds[index]
                                              if val == parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal blue-highlight"
                                              else if val > parseFloat(inputThresholds[index][0]) 
                                                td.className = "pvtGrandTotal green-highlight"
                                          else if threshOper[0]=='>' && threshOper[1]=='>' #9
                                            if inputThresholds[index]
                                              if val > parseFloat(inputThresholds[index][0]) || val > parseFloat(inputThresholds[index][1])
                                                td.className = "pvtGrandTotal green-highlight"
                            else
                                td.textContent = aggregator.format(val)
                            td.setAttribute("data-value", val)
                            if getClickHandler?
                                td.onclick = getClickHandler(val, [], [])
                            tr.appendChild td
                        tbody.appendChild tr
            else if colKeys.length > 0
                for attr,index in pivotData.valAttrs
                    tr = document.createElement("tr")
                    th = document.createElement("th")
                    th.className = "pvtTotalLabel pvtColTotalLabel"
                    th.innerHTML = attr
                    tr.appendChild th
                    for own i, colKey of colKeys
                        if percentAttribute
                            percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], colKeys[i] ,pivotData.filteredInput, 'col');
                        aggregator = pivotData.getAggregator([],colKey)
                        td = document.createElement("td")
                        td.className = "pvtGrandTotal"
                        val = aggregatorFunctions.multipleSum([attr], colKeys[i] ,pivotData.filteredInput, 'col')
                        if percentAttrVal && percentAttribute != attr
                            val = parseFloat(aggregator.format((val / percentAttrVal) * 100))
                            td.textContent = aggregator.format(val) + '%'
                            if inputOperator.length>0
                              threshOper = inputOperator[index];
                              if threshOper && threshOper.length>0
                                if threshOper.length==1 && threshOper[0]
                                  # 3 cases <,>,=
                                  if threshOper[0] == '<'
                                    if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal red-highlight"
                                  else if threshOper[0] == '='
                                    if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal blue-highlight"
                                  else if threshOper[0] == '>'
                                    if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal green-highlight"
                                else if threshOper.length==2
                                  if threshOper[0] && !threshOper[1]
                                    # 3 cases <,>,= paired with ''
                                    if threshOper[0] == '<'
                                      if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                        td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0] == '='
                                      if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                        td.className = "pvtGrandTotal blue-highlight"
                                    else if threshOper[0] == '>'
                                      if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                        td.className = "pvtGrandTotal green-highlight"
                                  else if !threshOper[0] && threshOper[1]
                                      # 3 cases <,>,= paired with ''
                                    if threshOper[1] == '<'
                                      if inputThresholds[index] && val < parseFloat(inputThresholds[index][1])
                                        td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[1] == '='
                                      if inputThresholds[index] && val == parseFloat(inputThresholds[index][1])
                                        td.className = "pvtGrandTotal blue-highlight"
                                    else if threshOper[1] == '>'
                                      if inputThresholds[index] && val > parseFloat(inputThresholds[index][1])
                                        td.className = "pvtGrandTotal green-highlight"
                                  else if threshOper[0] && threshOper[1]
                                      # 7 cases in total < & (<,>,=), > & (<,>,=), = & =
                                      if threshOper[0]=='<' && threshOper[1]=='<' #1
                                        if inputThresholds[index]
                                          if val < parseFloat(inputThresholds[index][0]) || val < parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='<' && threshOper[1]=='=' #2
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val < parseFloat(inputThresholds[index][0]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='<' && threshOper[1]=='>' #3
                                        if inputThresholds[index]
                                          if val > parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal green-highlight"
                                          else if val < parseFloat(inputThresholds[index][0]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='=' && threshOper[1]=='<' #4
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val < parseFloat(inputThresholds[index][1]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='=' && threshOper[1]=='=' #5
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][0]) || val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                      else if threshOper[0]=='=' && threshOper[1]=='>' #6
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val > parseFloat(inputThresholds[index][1]) 
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if threshOper[0]=='>' && threshOper[1]=='<' #7
                                        if inputThresholds[index]
                                          if val > parseFloat(inputThresholds[index][0])
                                            td.className = "pvtGrandTotal green-highlight"
                                          else if val < parseFloat(inputThresholds[index][1]) 
                                            td.className = "pvtGrandTotal red-highlight"
                                      else if threshOper[0]=='>' && threshOper[1]=='=' #8
                                        if inputThresholds[index]
                                          if val == parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal blue-highlight"
                                          else if val > parseFloat(inputThresholds[index][0]) 
                                            td.className = "pvtGrandTotal green-highlight"
                                      else if threshOper[0]=='>' && threshOper[1]=='>' #9
                                        if inputThresholds[index]
                                          if val > parseFloat(inputThresholds[index][0]) || val > parseFloat(inputThresholds[index][1])
                                            td.className = "pvtGrandTotal green-highlight"
                        else
                            td.textContent = aggregator.format(val)
                        tr.appendChild td

                    tbody.appendChild tr
            else
                for attr,index in pivotData.valAttrs
                    totalAggregator = pivotData.getAggregator([], [])
                    tr = document.createElement("tr")
                    if percentAttribute
                        percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], null ,pivotData.filteredInput, null);
                    if opts.table.colTotals || rowAttrs.length == 0
                        th = document.createElement("th")
                        th.className = "pvtTotalLabel pvtColTotalLabel"
                        th.innerHTML = attr
                        th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 0 else 1))
                        tr.appendChild th
                    if opts.table.rowTotals || colAttrs.length == 0
                        td = document.createElement("td")
                        td.className = "pvtGrandTotal"
                        val = aggregatorFunctions.multipleSum([attr], null ,pivotData.filteredInput, null)
                        if percentAttrVal && percentAttribute != attr
                            val = parseFloat(totalAggregator.format((val / percentAttrVal) * 100))
                            td.textContent = totalAggregator.format(val) + '%'
                            threshOper = inputOperator[index];
                            if threshOper && threshOper.length>0
                              if threshOper.length==1 && threshOper[0]
                                # 3 cases <,>,=
                                if threshOper[0] == '<'
                                  if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                    td.className = "pvtGrandTotal red-highlight"
                                else if threshOper[0] == '='
                                  if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                    td.className = "pvtGrandTotal blue-highlight"
                                else if threshOper[0] == '>'
                                  if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                    td.className = "pvtGrandTotal green-highlight"
                              else if threshOper.length==2
                                if threshOper[0] && !threshOper[1]
                                  # 3 cases <,>,= paired with ''
                                  if threshOper[0] == '<'
                                    if inputThresholds[index] && val < parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal red-highlight"
                                  else if threshOper[0] == '='
                                    if inputThresholds[index] && val == parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal blue-highlight"
                                  else if threshOper[0] == '>'
                                    if inputThresholds[index] && val > parseFloat(inputThresholds[index][0])
                                      td.className = "pvtGrandTotal green-highlight"
                                else if !threshOper[0] && threshOper[1]
                                    # 3 cases <,>,= paired with ''
                                  if threshOper[1] == '<'
                                    if inputThresholds[index] && val < parseFloat(inputThresholds[index][1])
                                      td.className = "pvtGrandTotal red-highlight"
                                  else if threshOper[1] == '='
                                    if inputThresholds[index] && val == parseFloat(inputThresholds[index][1])
                                      td.className = "pvtGrandTotal blue-highlight"
                                  else if threshOper[1] == '>'
                                    if inputThresholds[index] && val > parseFloat(inputThresholds[index][1])
                                      td.className = "pvtGrandTotal green-highlight"
                                else if threshOper[0] && threshOper[1]
                                    # 7 cases in total < & (<,>,=), > & (<,>,=), = & =
                                    if threshOper[0]=='<' && threshOper[1]=='<' #1
                                      if inputThresholds[index]
                                        if val < parseFloat(inputThresholds[index][0]) || val < parseFloat(inputThresholds[index][1])
                                          td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0]=='<' && threshOper[1]=='=' #2
                                      if inputThresholds[index]
                                        if val == parseFloat(inputThresholds[index][1])
                                          td.className = "pvtGrandTotal blue-highlight"
                                        else if val < parseFloat(inputThresholds[index][0]) 
                                          td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0]=='<' && threshOper[1]=='>' #3
                                      if inputThresholds[index]
                                        if val > parseFloat(inputThresholds[index][1])
                                          td.className = "pvtGrandTotal green-highlight"
                                        else if val < parseFloat(inputThresholds[index][0]) 
                                          td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0]=='=' && threshOper[1]=='<' #4
                                      if inputThresholds[index]
                                        if val == parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal blue-highlight"
                                        else if val < parseFloat(inputThresholds[index][1]) 
                                          td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0]=='=' && threshOper[1]=='=' #5
                                      if inputThresholds[index]
                                        if val == parseFloat(inputThresholds[index][0]) || val == parseFloat(inputThresholds[index][1])
                                          td.className = "pvtGrandTotal blue-highlight"
                                    else if threshOper[0]=='=' && threshOper[1]=='>' #6
                                      if inputThresholds[index]
                                        if val == parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal blue-highlight"
                                        else if val > parseFloat(inputThresholds[index][1]) 
                                          td.className = "pvtGrandTotal green-highlight"
                                    else if threshOper[0]=='>' && threshOper[1]=='<' #7
                                      if inputThresholds[index]
                                        if val > parseFloat(inputThresholds[index][0])
                                          td.className = "pvtGrandTotal green-highlight"
                                        else if val < parseFloat(inputThresholds[index][1]) 
                                          td.className = "pvtGrandTotal red-highlight"
                                    else if threshOper[0]=='>' && threshOper[1]=='=' #8
                                      if inputThresholds[index]
                                        if val == parseFloat(inputThresholds[index][1])
                                          td.className = "pvtGrandTotal blue-highlight"
                                        else if val > parseFloat(inputThresholds[index][0]) 
                                          td.className = "pvtGrandTotal green-highlight"
                                    else if threshOper[0]=='>' && threshOper[1]=='>' #9
                                      if inputThresholds[index]
                                        if val > parseFloat(inputThresholds[index][0]) || val > parseFloat(inputThresholds[index][1])
                                          td.className = "pvtGrandTotal green-highlight"
                        else
                            td.textContent = totalAggregator.format(val)
                        td.setAttribute("data-value", val)
                        if getClickHandler?
                            td.onclick = getClickHandler(val, [], [])
                        tr.appendChild td
                    tbody.appendChild tr 
        
        #Single Aggregator Scenario
        else
            # To hide hiding entire row total --------------------------------------------- rohan
            totalAggregator = pivotData.getAggregator([], [])
            valRowTotal = totalAggregator.value()
            # console.log typeof val
            # console.log "hiding entire row total when value is: "+val
            if typeof valRowTotal != "string"
                # console.log "not hiding entire row total: inside if block"
                #finally, the row for col totals, and a grand total
                if opts.table.colTotals || rowAttrs.length == 0
                    tr = document.createElement("tr")
                    if isMultiple == false
                        if opts.table.colTotals || rowAttrs.length == 0
                            th = document.createElement("th")
                            th.className = "pvtTotalLabel pvtColTotalLabel"
                            # th.innerHTML = opts.localeStrings.totals + " of " + "<span id='rowCountColor'>" + rowKeys.length + "</span>" + " rows" -------- rohan
                            th.innerHTML = "Total of " + "<span id='rowCountColor'>" + rowKeys.length + "</span>" + " rows"
                            th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 1 else 2)) # ---------------------- rohan
                            # conditional spanning of "Total" ---------------------- rohan
                            # if rowAttrs.length > 1
                            #     th.setAttribute("colspan", rowAttrs.length + 1)
                            # else
                            #     th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 1 else 2))
                            # -------------------------------------------------
                            tr.appendChild th
                    for own j, colKey of colKeys
                        totalAggregator = pivotData.getAggregator([], colKey)
                        val = totalAggregator.value()
                        td = document.createElement("td")
                        td.className = "pvtTotal colTotal"
                        td.textContent = totalAggregator.format(val)
                        td.setAttribute("data-value", val)
                        if getClickHandler?
                            td.onclick = getClickHandler(val, [], colKey)
                        td.setAttribute("data-for", "col"+j)
                        tr.appendChild td
                    if opts.table.rowTotals || colAttrs.length == 0
                        totalAggregator = pivotData.getAggregator([], [])
                        val = totalAggregator.value()
                        td = document.createElement("td")
                        td.className = "pvtGrandTotal"
                        td.textContent = totalAggregator.format(val)
                        td.setAttribute("data-value", val)
                        if getClickHandler?
                            td.onclick = getClickHandler(val, [], [])
                        tr.appendChild td
                    tbody.appendChild tr

            customSerialNo = 1
            for own i, rowKey of rowKeys
                tr = document.createElement("tr")
                # # Serial numbers for each row -------- rohan
                # th = document.createElement("th")
                # th.textContent = parseInt(i) + 1
                # th.setAttribute("rowspan", count)
                # tr.appendChild th
                # # ------------------------------------
                for own j, txt of rowKey
                    x = spanSize(rowKeys, parseInt(i), parseInt(j))
                    if x != -1
                        if x > 1 and parseInt(j) == 0
                            # Serial numbers for each row -------- rohan
                            th = document.createElement("th")
                            th.textContent = customSerialNo
                            th.setAttribute("rowspan", x)
                            tr.appendChild th
                            # ------------------------------------
                            customSerialNo++
                        # if x == 1 and rowKeys[i][0] == txt and colAttrs.length ==0
                        if x == 1 and colAttrs.length ==0 and parseInt(j) == 0
                            # Serial numbers for each row -------- rohan
                            th = document.createElement("th")
                            th.textContent = customSerialNo
                            th.setAttribute("rowspan", x)
                            tr.appendChild th
                            # ------------------------------------
                            customSerialNo++
                        # if x == 1 and colAttrs.length !=0
                        if x == 1 and colAttrs.length !=0 and parseInt(j) == 0
                            # Serial numbers for each row -------- rohan
                            th = document.createElement("th")
                            th.textContent = parseInt(i) + 1
                            tr.appendChild th
                            # ------------------------------------
                        th = document.createElement("th")
                        th.className = "pvtRowLabel"
                        th.textContent = txt
                        th.setAttribute("rowspan", x)
                        if parseInt(j) == rowAttrs.length-1 and colAttrs.length !=0
                            th.setAttribute("colspan",2)
                        tr.appendChild th
                for own j, colKey of colKeys #this is the tight loop
                    aggregator = pivotData.getAggregator(rowKey, colKey)
                    val = aggregator.value()
                    td = document.createElement("td")
                    td.className = "pvtVal row#{i} col#{j}"
                    td.textContent = aggregator.format(val)
                    td.setAttribute("data-value", val)
                    if getClickHandler?
                        td.onclick = getClickHandler(val, rowKey, colKey)
                    tr.appendChild td

                if opts.table.rowTotals || colAttrs.length == 0
                    # To hide each value field of each row --------------------------------------------- rohan
                    totalAggregator = pivotData.getAggregator(rowKey, [])
                    valEachRow = totalAggregator.value()
                    if typeof valEachRow != "string"
                        # console.log "pvtTotal rowTotal -> td: "+val
                        td = document.createElement("td")
                        td.className = "pvtTotal rowTotal"
                        # td.textContent = totalAggregator.format(val)
                        td.textContent = totalAggregator.format(valEachRow)
                        # td.setAttribute("data-value", val)
                        td.setAttribute("data-value", valEachRow)
                        if getClickHandler?
                            # td.onclick = getClickHandler(val, rowKey, [])
                            td.onclick = getClickHandler(valRowTotal, rowKey, [])
                        td.setAttribute("data-for", "row"+i)
                        tr.appendChild td
                tbody.appendChild tr

            #finally, the row for col totals, and a grand total
            # if opts.table.colTotals || rowAttrs.length == 0
            #     tr = document.createElement("tr")
            #     if isMultiple == false
            #         if opts.table.colTotals || rowAttrs.length == 0
            #             th = document.createElement("th")
            #             th.className = "pvtTotalLabel pvtColTotalLabel"
            #             th.innerHTML = opts.localeStrings.totals
            #             th.setAttribute("colspan", rowAttrs.length + (if colAttrs.length == 0 then 0 else 1))
            #             tr.appendChild th
            #     for own j, colKey of colKeys
            #         totalAggregator = pivotData.getAggregator([], colKey)
            #         val = totalAggregator.value()
            #         td = document.createElement("td")
            #         td.className = "pvtTotal colTotal"
            #         td.textContent = totalAggregator.format(val)
            #         td.setAttribute("data-value", val)
            #         if getClickHandler?
            #             td.onclick = getClickHandler(val, [], colKey)
            #         td.setAttribute("data-for", "col"+j)
            #         tr.appendChild td
            #     if opts.table.rowTotals || colAttrs.length == 0
            #         totalAggregator = pivotData.getAggregator([], [])
            #         val = totalAggregator.value()
            #         td = document.createElement("td")
            #         td.className = "pvtGrandTotal"
            #         td.textContent = totalAggregator.format(val)
            #         td.setAttribute("data-value", val)
            #         if getClickHandler?
            #             td.onclick = getClickHandler(val, [], [])
            #         tr.appendChild td
            #     tbody.appendChild tr
        result.appendChild tbody

        # percentAttribute = "";
        
        #squirrel this away for later
        result.setAttribute("data-numrows", rowKeys.length)
        result.setAttribute("data-numcols", colKeys.length)
        
        tableWrapper = document.createElement("div");
        tableWrapper.className = "table-wrapper"
        tableWrapper.setAttribute("data-numrows", rowKeys.length)
        tableWrapper.setAttribute("data-numcols", colKeys.length)

        tableWrapper.append(result)

        return tableWrapper
