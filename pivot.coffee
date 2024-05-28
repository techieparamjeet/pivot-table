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
