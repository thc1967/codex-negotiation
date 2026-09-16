local mod = dmhub.GetModLoading()

--- Two closing surfaces: the Director's summary, where the Victories are set
--- and handed out, and the celebration the whole table sees afterwards.
NEGEndingPanel = RegisterGameType("NEGEndingPanel")

--- One line of the report: a section's title or one of its entries. Built once
--- and handed a line with `setLine`; the label inside is remade only when the
--- line moves, which after the report is frozen is never.
--- @return Panel
local function ReportLine()
    return NEGWidgets.BoundRow{
        width = "100%",
        --- @param line nil|{kind: string, text: string}
        setLine = function(row, line)
            local state = ""
            if line ~= nil then
                state = line.kind .. "|" .. line.text
            end
            NEGWidgets.SetBoundRow(row, state, function()
                if line.kind == "header" then
                    return THCWidgets.SubHeader(line.text, "sizeXl")
                end
                return gui.Label{
                    classes = { "sizeM", "noBold" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    markdown = true,
                    text = string.format("- %s", line.text),
                }
            end)
        end,
    }
end

--- The Director's summary. Lives in the negotiation window and reads the live
--- Run, so the Victories can still be changed. Nothing has gone out to the
--- table yet. Complete goes to the shell's footer, so this hands it out rather
--- than mounting it.
--- @param opts nil|{director: boolean}
--- @return {body: Panel, footer: table[]}
function NEGEndingPanel.Create(opts)
    opts = opts or {}
    local director = opts.director == true

    local reportPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local m_resultText = nil

    --Unlike a montage the result is not a judgement call: the interest the
    --negotiation closed on names the offer outright, so this reads rather
    --than picks.
    local resultLabel = gui.Label{
        classes = { "sizeL" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        markdown = true,
        text = "",
    }

    local m_detailText = nil

    local detailLabel = gui.Label{
        classes = { "sizeM", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 2,
        bmargin = 4,
        markdown = true,
        textWrap = true,
        text = "",
    }

    local trophyIcon = gui.Panel{
        classes = { "image" },
        width = 28,
        height = 28,
        halign = "left",
        valign = "center",
        rmargin = 6,
        bgimage = NEGConstants.iconVictory,
    }

    local victoryLabel = gui.Label{
        classes = { "sizeL" },
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        rmargin = 8,
        text = "Victories",
    }

    local victoryInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        width = 60,
        height = 22,
        halign = "left",
        valign = "center",
        text = "0",
        change = function(element)
            NEGRun.SetEndingVictories(tonumber(element.text) or 0)
        end,
    }

    local endingControls = gui.Panel{
        classes = { cond(not director, "collapsed") },
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        vmargin = 8,

        trophyIcon,
        victoryLabel,
        victoryInput,
    }

    local completeButton = gui.Button{
        classes = { "sizeL" },
        width = 120,
        text = "Complete",
        halign = "right",
        valign = "center",
        hover = gui.Tooltip("Award the Victories, announce the result, clear the negotiation"),
        click = function()
            --A value typed and never blurred has not reached the Run yet.
            NEGRun.SetEndingVictories(tonumber(victoryInput.text) or 0)
            NEGRun.CompleteRun()
        end,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",

        monitorGame = NEGRun.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local live = NEGRun.Active()
            local ending = live ~= nil and live:try_get("ending") or nil
            if ending == nil then
                return
            end

            local lines = {}
            for _, section in ipairs(ending.sections or {}) do
                lines[#lines + 1] = { kind = "header", text = section.title or "" }
                for _, entry in ipairs(section.entries or {}) do
                    lines[#lines + 1] = { kind = "entry", text = entry }
                end
            end
            THCWidgets.BindList(reportPanel, lines, ReportLine, "setLine")

            --Halved for a devil: the ladder is always read 0..5.
            local interest = live:ResultInterest()

            local result = string.format("**Result:** %s", NEGRules.OfferName(interest))
            if m_resultText ~= result then
                m_resultText = result
                resultLabel.text = result
            end

            local detail = live:OfferText()
            detailLabel:SetClass("collapsed", trim(detail) == "")
            if m_detailText ~= detail then
                m_detailText = detail
                detailLabel.text = detail
            end

            local victories = tostring(ending.victories or 0)
            if victoryInput.text ~= victories then
                victoryInput.text = victories
            end
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        resultLabel,
        detailLabel,
        endingControls,

        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "vertical",
            valign = "top",
            vscroll = true,

            reportPanel,
        },
    }

    return {
        body = resultPanel,
        footer = {
            {},
            {},
            { slot = cond(director, completeButton) },
        },
    }
end

--- The celebration the whole table sees once the Director is done. Renders
--- entirely from the payload, so the Run can be cleared the moment this goes
--- out.
--- @param payload table
--- @return Panel
function NEGEndingPanel.CreateCelebration(payload)
    local ending = payload.ending or {}

    return THCWidgets.Celebration{
        title = cond(payload.npcName ~= nil and payload.npcName ~= "",
            payload.npcName, payload.name or "Negotiation"),
        subtitle = payload.result or "",
        detail = payload.detail or "",
        victories = ending.victories or 0,
        icon = NEGConstants.iconVictory,
        recap = payload.recap,

        RecapLines = function(row)
            local lines = {}
            if row.led > 0 or row.assisted > 0 then
                lines[#lines + 1] = string.format("Led %d  |  Assisted %d", row.led, row.assisted)
            else
                lines[#lines + 1] = "Stood by"
            end
            if row.read > 0 then
                lines[#lines + 1] = string.format("Read the room %d", row.read)
            end
            if row.bestTier ~= nil then
                lines[#lines + 1] = string.format("Best Tier %d", row.bestTier)
            end
            return lines
        end,
    }
end
