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
                    percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], rowKeys[i] ,pivotData.filteredInput, 'row')
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
                        val = aggregatorFunctions.multipleSum([attr], rowKeys[i], pivotData.filteredInput, 'row')
                        if percentAttrVal && percentAttribute != attr
                            val = parseFloat(aggregator.format((val / percentAttrVal) * 100))
                            td.textContent = aggregator.format(val) + '%'
                            if inputOperator.length > 0
                                # Optimized threshold check
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
                    percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], colKeys[i] ,pivotData.filteredInput, 'col')
                aggregator = pivotData.getAggregator([], colKey)
                td = document.createElement("td")
                td.className = "pvtGrandTotal"
                val = aggregatorFunctions.multipleSum([attr], colKeys[i], pivotData.filteredInput, 'col')
                if percentAttrVal && percentAttribute != attr
                    val = parseFloat(aggregator.format((val / percentAttrVal) * 100))
                    td.textContent = aggregator.format(val) + '%'
                    if inputOperator.length > 0
                        # Optimized threshold check
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
                percentAttrVal = aggregatorFunctions.multipleSum([percentAttribute], null ,pivotData.filteredInput, null)
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
                        if inputOperator.length > 0
                            # Optimized threshold check
                    else
                        td.textContent = totalAggregator.format(val)
                    td.setAttribute("data-value", val)
                    if getClickHandler?
                        td.onclick = getClickHandler(val, [], [])
                    tr.appendChild td
            tbody.appendChild tr
