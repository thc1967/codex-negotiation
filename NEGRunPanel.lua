local mod = dmhub.GetModLoading()

--- The negotiation in play. One body serves both sides: the Director's carries
--- the live scales and the eyes; the players' carries only what is revealed.
NEGRunPanel = RegisterGameType("NEGRunPanel")

--- A form label over its value, matching the configuration screen.
--- @param labelText string
--- @param width string
--- @param control Panel
--- @return Panel
local function Field(labelText, width, control)
    --Not formStackedRow: its lmargin 12 / bmargin 8 are far too loose for a
    --read-only strip of facts.
    return gui.Panel{
        width = width,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        bmargin = 4,

        gui.Label{
            classes = { "sizeS" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            text = labelText,
        },

        control,
    }
end

--- The value under a field label. Dim, and uniform across all of them.
--- @param args nil|table extra panel args, e.g. markdown or textWrap
--- @return Panel
local function FieldValue(args)
    local panelArgs = {
        classes = { "sizeS", "noBold", "fgMuted" },
        width = "98%",
        height = "auto",
        halign = "left",
        valign = "top",
        text = "",
    }

    for key, value in pairs(args or {}) do
        panelArgs[key] = value
    end

    return gui.Label(panelArgs)
end

--- One motivation or pitfall: the Director's eye, the pitfall gavel, the trait,
--- and its note.
--- @param entry table a NEGRun.Traits row
--- @param kind string "motivations" or "pitfalls"
--- @param director boolean
--- @return Panel
local function TraitRow(entry, kind, director)
    --The table gets one line of prose, not a row of controls.
    if not director then
        return gui.Label{
            classes = { "sizeS", "noBold", "fgMuted" },
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 4,
            textWrap = true,
            markdown = true,
            text = string.format("**%s:** %s", entry.name, entry.note),
        }
    end

    local children = {
        NEGWidgets.EyeToggle{
            shown = entry.revealed,
            change = function(shown)
                NEGRun.SetTraitRevealed(entry.id, shown)
            end,
        },
    }

    --The rules settle a pitfall without a roll, so this button is the whole
    --resolution: both scales pay, and the argument comes off the floor.
    if kind == "pitfalls" then
        children[#children + 1] = gui.Button{
            classes = { "sizeS", "withDanger" },
            icon = NEGConstants.iconPitfall,
            halign = "left",
            valign = "center",
            lmargin = 6,
            hover = THCWidgets.Tooltip(
                "They argued into this pitfall. No roll: interest -1, patience -1, "
                .. "the pitfall is shown to the table, and the argument's heroes go "
                .. "back to the tray spent."),
            click = function()
                NEGRun.HitPitfall(entry.id)
            end,
        }
    end

    children[#children + 1] = gui.Label{
        classes = { "sizeS" },
        width = "100% available",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = cond(director, 6, 0),
        text = entry.name,
    }

    local rows = {
        gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            children = children,
        },
    }

    if trim(entry.note) ~= "" then
        rows[#rows + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%-24",
            height = "auto",
            halign = "right",
            valign = "top",
            tmargin = 1,
            textWrap = true,
            text = entry.note,
        }
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vmargin = 4,
        children = rows,
    }
end

--- One side of the traits pane, alphabetical by trait.
--- @param live NEGLive
--- @param kind string
--- @param title string
--- @param director boolean
--- @return Panel
local function TraitColumn(live, kind, title, director)
    local entries = NEGRun.Traits(live, kind)

    local children = {
        gui.Label{
            classes = { "sizeL" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            bmargin = 4,
            text = title,
        },
    }

    local shown = 0
    for _, entry in ipairs(entries) do
        if director or entry.revealed then
            shown = shown + 1
            children[#children + 1] = TraitRow(entry, kind, director)
        end
    end

    if shown == 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 6,
            textAlignment = "left",
            text = cond(director, "None yet.", "Nothing revealed."),
        }
    end

    return gui.Panel{
        width = NEGConstants.traitColumnWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = NEGConstants.traitColumnGap,
        children = children,
    }
end

--- One hero, and whether they are at this table.
--- @param p NEGParticipant
--- @param index number
--- @return Panel
local function ParticipantRow(p, index)
    local charid = p.charid
    local token = dmhub.GetCharacterById(charid)

    local children = {
        gui.Check{
            classes = { "sizeS" },
            text = "",
            width = 30,
            minWidth = 1,
            value = p:try_get("included", true),
            halign = "left",
            valign = "center",
            change = function(element)
                NEGRun.SetParticipantIncluded(charid, element.value)
            end,
        },
    }

    if token ~= nil then
        children[#children + 1] = gui.CreateTokenImage(token, {
            width = NEGConstants.participantImageSize,
            height = NEGConstants.participantImageSize,
            halign = "left",
            valign = "center",
        })
    end

    children[#children + 1] = gui.Label{
        classes = { "sizeS" },
        width = "auto",
        height = "auto",
        lmargin = 8,
        halign = "left",
        valign = "center",
        text = p:try_get("name", ""),
    }

    return gui.Panel{
        classes = { "row", cond(index % 2 == 1, "oddRow", "evenRow") },
        width = "100%",
        height = NEGConstants.participantRowHeight,
        flow = "horizontal",
        valign = "top",
        children = children,
    }
end

--- Who is at the table, and what that does to the NPC's patience. Nothing is
--- committed until Start.
--- @return {body: Panel, footer: table[]}
function NEGRunPanel.CreateSetup()
    local titleLabel = gui.Label{
        classes = { "sizeL" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        textWrap = true,
        text = "",
    }

    local openingLabel = gui.Label{
        classes = { "sizeS", "noBold", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        textWrap = true,
        text = "",
    }

    local rosterPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
    }

    local body
    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",

        negotiationChanged = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local live = NEGRun.Active()
            if live == nil then
                return
            end

            local npc = live:NpcName()
            titleLabel.text = cond(npc ~= "", npc, live:Name())

            local patience, bonus, speakers = NEGRun.PreviewOpening(live)
            local def = live:Definition()
            local language = NEGRules.LanguageName(
                def ~= nil and def:try_get("languageId", "") or "")

            if bonus > 0 then
                openingLabel.text = string.format(
                    "Opens at Interest %d, Patience %d. %d of them %s %s, for +%d patience.",
                    live.interest, patience, #speakers,
                    cond(#speakers == 1, "speaks", "speak"), language, bonus)
            elseif language ~= "" then
                openingLabel.text = string.format(
                    "Opens at Interest %d, Patience %d. Nobody here speaks %s.",
                    live.interest, patience, language)
            else
                openingLabel.text = string.format(
                    "Opens at Interest %d, Patience %d.", live.interest, patience)
            end

            --Companions are left out: they follow the hero they belong to, so
            --there is nothing here for the Director to decide.
            local rows = {}
            for i, p in ipairs(live:try_get("participants", {})) do
                if not p.isCompanion then
                    rows[#rows + 1] = ParticipantRow(p, i)
                end
            end

            if #rows == 0 then
                rows[1] = gui.Label{
                    classes = { "sizeS", "noBold", "fgMuted" },
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    vmargin = 8,
                    text = "No heroes found.",
                }
            end

            rosterPanel.children = rows
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        titleLabel,
        openingLabel,

        gui.Panel{
            width = NEGConstants.sectionWidth,
            height = "100% available",
            flow = "vertical",
            halign = "left",
            valign = "top",
            tmargin = 12,
            vscroll = true,

            NEGWidgets.SectionHeader{ text = "Who Is Negotiating" },
            rosterPanel,
        },
    }

    return {
        body = body,
        footer = {
            {
                slot = gui.Button{
                    classes = { "sizeL" },
                    text = "Cancel",
                    halign = "left",
                    valign = "center",
                    hover = THCWidgets.Tooltip("Back to the library. Nothing is kept."),
                    click = function()
                        NEGRun.Discard()
                    end,
                },
            },
            {},
            {
                slot = gui.Button{
                    classes = { "sizeL" },
                    text = "Start",
                    halign = "right",
                    valign = "center",
                    click = function(element)
                        NEGRun.Start()
                        NEGRun.PresentToPlayers(element)
                    end,
                },
            },
        },
    }
end

--- One track: its seats, their picks and rolls, the Director's next step, and
--- the tier table the Lead's roll lands on. The rolls themselves are
--- THCRollFlow's; what stays here is Negotiation's own furniture - Renown,
--- the appeal, the hidden Assist, the curtains.
--- @param live NEGLive
--- @param args {track: string, title: string, width: string, director: boolean, slots: {key: string, label: string}[]}
--- @return Panel
local function TrackPanel(live, args)
    local track = args.track
    local flow = NEGRun.Flow(track)
    local record = NEGRun.Record(live, track)
    local eff = flow:Effective()

    local pending = record.pending
    local rolling = pending ~= nil
    local leadRoll = record.rolls[THCRollFlow.slotLead]
    local assistRoll = record.rolls[THCRollFlow.slotAssist]
    local accepted = record.accepted == true

    --The curtain only stops clicks; a drop target is a separate mechanism, so
    --the lockout has to make the seats inert as well.
    local locked = track == NEGConstants.trackLearn
        and live:try_get("learnLocked", false)

    --Staffed means a hero is standing in the track; settled means one of its
    --seats holds a roll.
    local staffed = next(eff) ~= nil
    local settled = next(record.rolls) ~= nil

    --Patience is spent, so nothing here can roll again. The table is told at
    --once. The Director keeps the track until they have cleared out whoever was
    --standing in it, so the roll that ended the negotiation can still be read
    --and reset rather than being curtained off mid-resolution.
    local expired = live.patience <= NEGConstants.scaleMin
        and (not args.director or not (staffed or settled))

    local canStage = NEGRun.CanStage(live, track)
    local free = NEGRun.FreeHeroes(live)

    --The die: send the first roll, take back the one out, or clear the track
    --once anything has rolled - whatever else is waiting, so a track never
    --sticks.
    local dieButton
    if not args.director then
        dieButton = gui.Panel{
            width = 0,
            height = 0,
        }
    elseif rolling then
        dieButton = gui.Button{
            classes = { "sizeXs" },
            icon = NEGConstants.iconRoll,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 8,
            hover = THCWidgets.Tooltip("Waiting on the roll. Press to take it back."),
            click = function()
                NEGRun.CancelRoll(track)
            end,
        }
    elseif settled then
        dieButton = gui.Button{
            classes = { "sizeXs" },
            icon = NEGConstants.iconReset,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 8,
            hover = THCWidgets.Tooltip("Clear this track. Whoever rolled goes back to the tray, spent."),
            click = function()
                NEGRun.ResetTrack(track)
            end,
        }
    else
        local blocker = nil
        if flow:NextSlot() == nil then
            blocker = string.format("Put a hero in the %s slot first", args.slots[1].label)
        elseif not flow:CanRoll() then
            blocker = "This track cannot roll now."
        else
            blocker = flow:SendBlocker()
        end
        dieButton = gui.Button{
            classes = { "sizeXs", cond(blocker == nil, nil, "disabled") },
            icon = NEGConstants.iconRoll,
            width = 22,
            height = 22,
            halign = "left",
            valign = "center",
            rmargin = 8,
            hover = THCWidgets.Tooltip(blocker or "Request rolls"),
            click = function(element)
                if element:HasClass("disabled") then
                    return
                end
                NEGRun.Roll(track)
            end,
        }
    end

    --The step after a roll sits on the seat that rolled, beside its Re-roll:
    --the Lead's turn once the Assist is in, then the Director taking the
    --Lead's roll.
    local steps = {}
    if args.director and not rolling and not accepted then
        if leadRoll ~= nil then
            steps[THCRollFlow.slotLead] = {
                text = "Accept",
                enabled = true,
                tooltip = "Take this roll: the scales move and the track can no longer re-roll.",
                run = function()
                    NEGRun.AcceptTrack(track)
                end,
            }
        elseif assistRoll ~= nil then
            local blocker = cond(flow:CanRoll(), flow:SendBlocker(), "This track cannot roll now.")
            steps[THCRollFlow.slotAssist] = {
                text = "Continue",
                enabled = blocker == nil,
                tooltip = blocker or "Ask the Lead to roll.",
                run = function()
                    NEGRun.Roll(track)
                end,
            }
        end
    end

    --Fixed height, and the label sized in pixels. An auto-height label taking
    --"100% available" inside a horizontal flow resolves to something enormous.
    local children = {
        gui.Panel{
            width = "100%",
            height = 26,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            bmargin = 2,

            dieButton,

            gui.Label{
                classes = { "sizeL" },
                width = "100%-30",
                height = "100%",
                halign = "left",
                valign = "center",
                text = args.title,
            },
        },
    }

    --Units share a line. The track's width is set by how many it holds, so a
    --unit is the same size in either track.
    local units = {}
    local unitWidth = string.format("%d%%", math.floor(100 / math.max(1, #args.slots)))

    for _, slot in ipairs(args.slots) do
        local slotKey = slot.key
        local entry = record.slots[slotKey]
        local assignment = eff[slotKey]
        local roll = record.rolls[slotKey]

        --Renown rides with the argument's two seats, which is where it is
        --weighed against the NPC's Impression.
        local renown = nil
        if assignment ~= nil and track == NEGConstants.trackArgument then
            renown = NEGRules.Renown(assignment.charid)
        end

        --Only the Assist can be kept back, and only the Director decides it.
        local assistEye = nil
        if args.director and slotKey == THCRollFlow.slotAssist then
            local assistShown = not live:try_get("assistHidden", false)
            assistEye = NEGWidgets.EyeToggle{
                shown = assistShown,
                size = 12,
                lmargin = 4,
                tooltipShown = "The table can see the Assist. Click to hide it.",
                tooltipHidden = "The Assist is hidden from the table. Click to show it.",
                change = function(shown)
                    NEGRun.SetAssistHidden(not shown)
                end,
            }
        end

        local column = {}

        if assignment ~= nil and roll == nil then
            local pickers = THCRollWidgets.Pickers{
                characteristic = "Not one of the negotiation characteristics",
            }
            pickers:FireEvent("setPickers", flow, slotKey, eff,
                flow:CanEdit(slotKey) and NEGRun.CanManage(assignment.charid))
            column[#column + 1] = pickers

            --Set before the die goes out: the appeal decides which ladder the
            --Lead's tier is read against, and Renown edges that seat's own roll.
            if args.director and track == NEGConstants.trackArgument and flow:CanEdit(slotKey) then
                local toggles = {}

                --The heart picks the ladder the argument's own tier is read
                --against, which is the lead's business. An assist's tier never
                --meets that ladder - it becomes the grant it hands the lead.
                if slotKey == THCRollFlow.slotLead then
                    local appealing = live:try_get("appealMotivation", false)

                    toggles[#toggles + 1] = gui.Panel{
                        classes = { cond(appealing, "bgSuccess", "bgFgMuted") },
                        width = 20,
                        height = 20,
                        halign = "left",
                        valign = "center",
                        bgimage = NEGConstants.iconMotivation,
                        hover = THCWidgets.Tooltip(cond(appealing,
                            "Appealing to motivation",
                            "Not appealing to motivation")),
                        press = function()
                            NEGRun.SetAppealMotivation(not appealing)
                        end,
                    }
                end

                local edging = entry ~= nil and entry.renownEdge == true

                toggles[#toggles + 1] = gui.Panel{
                    classes = { cond(edging, "bgSuccess", "bgFgMuted") },
                    width = 20,
                    height = 20,
                    halign = "left",
                    valign = "center",
                    lmargin = cond(#toggles > 0, 6, 0),
                    bgimage = NEGConstants.iconRenown,
                    hover = THCWidgets.Tooltip(cond(edging,
                        "Influencing with Renown",
                        "Not influencing with Renown")),
                    press = function()
                        flow:SetSlotField(slotKey, "renownEdge", not edging, "Set Renown")
                    end,
                }

                column[#column + 1] = gui.Panel{
                    width = "98%",
                    height = 24,
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    vmargin = 1,
                    children = toggles,
                }
            end
        end

        local rollLines = THCRollWidgets.RollLines()
        rollLines:FireEvent("setRoll", flow, slotKey, eff)
        column[#column + 1] = rollLines

        --What the Lead's roll does to the scales. Withheld unless open: it is
        --read against the chosen ladder, so a table that sees it can derive the
        --NPC's motivations.
        if slotKey == THCRollFlow.slotLead and roll ~= nil
            and (args.director or live:try_get("open", false)) then
            local outcome = NEGRun.Outcome(live, track)
            if outcome ~= nil and outcome.text ~= "" then
                column[#column + 1] = gui.Label{
                    classes = { "sizeXs", "noBold", "warning" },
                    width = "98%",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    tmargin = 2,
                    textWrap = true,
                    text = cond(accepted, outcome.text, string.format("If taken: %s", outcome.text)),
                }
            end
        end

        if args.director then
            local offline = THCRollWidgets.OfflineNotice()
            offline:FireEvent("setCharid", (assignment ~= nil and roll == nil) and assignment.charid or nil)
            column[#column + 1] = offline

            local buttons = THCRollWidgets.DirectorButtons()
            buttons:FireEvent("setButtons", flow, slotKey, steps[slotKey])
            column[#column + 1] = buttons
        end

        units[#units + 1] = gui.Panel{
            classes = { cond(not args.director
                and slotKey == THCRollFlow.slotAssist
                and live:try_get("assistHidden", false), "collapsed") },
            width = unitWidth,
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            NEGWidgets.Slot{
                label = slot.label,
                charid = assignment ~= nil and assignment.charid or nil,
                name = assignment ~= nil and NEGRun.ParticipantName(live, assignment.charid) or "",
                renown = renown,
                labelTrailing = assistEye,
                inert = not canStage,
                --A filled seat must be emptied first, so it offers only Remove.
                options = cond(assignment ~= nil, {}, free),
                place = function(charid)
                    flow:Stage(slotKey, charid)
                end,
                clear = function()
                    flow:Unstage(slotKey)
                end,
            },

            gui.Panel{
                width = "96%-54",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                children = column,
            },
        }
    end

    children[#children + 1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        children = units,
    }

    --Appended last, which is what puts it on top. A spent read is barred on
    --both sides, so both get that curtain. A roll still out curtains only the
    --table: covering the Director's would take away the die that recalls it.
    --Expiry outranks the rest - it is the end of the negotiation, not a wait.
    local curtainText = nil

    if expired then
        curtainText = "Patience expired"
    elseif not args.director and rolling then
        curtainText = "Rolling..."
    elseif locked then
        curtainText = "Just Rolled"
    end

    if curtainText ~= nil then
        local curtain = THCWidgets.Overlay(curtainText, "sizeL", 1, 0)
        curtain:SetClass("collapsed", false)
        children[#children + 1] = curtain
    end

    return gui.Panel{
        width = args.width,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = NEGConstants.traitColumnGap,
        children = children,
    }
end

--- @param args {director: boolean}
--- @return {body: Panel}
function NEGRunPanel.Create(args)
    local director = args.director == true

    local impressionLabel = FieldValue()

    --Read-only in play. The patience it earns was banked when the negotiation
    --opened, so there is nothing here for a change to act on.
    local languageLabel = FieldValue()

    local openCheck = gui.Check{
        classes = { "sizeS" },
        text = "Open",
        width = "100%",
        height = 24,
        halign = "left",
        valign = "center",
        hover = THCWidgets.Tooltip(
            "Show the table both scales, the offer, and the real tier outcomes on "
            .. "their roll dialogs. Motivations and pitfalls stay behind their eyes."),
        change = function(element)
            NEGRun.SetOpen(element.value)
        end,
    }

    local statsRow = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",

        Field("Impression", "40%", impressionLabel),
        Field("Native Language", "30%", languageLabel),
        Field("Sharing", "20%", openCheck),
    }

    local summaryLabel = FieldValue{ textWrap = true, markdown = true }

    local summaryPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        Field("Scenario", "98%", summaryLabel),
    }

    local scalesPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }

    local terminalLabel = gui.Label{
        classes = { "sizeS", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        textWrap = true,
        text = "",
    }

    --What the NPC is saying at this interest. The Director's to read out, so
    --it is never built into a player's window.
    --Holds a line's height even when empty, so a withheld offer reads as "not
    --yet" rather than as nothing to say.
    local offerLabel = FieldValue{
        textWrap = true,
        markdown = true,
        minHeight = 22,
    }

    --Lit means the table is looking at this offer right now. It goes dim the
    --moment interest moves, because that is a different offer.
    local shareButton = gui.Panel{
        classes = { "bgFgPending" },
        width = 20,
        height = 20,
        halign = "left",
        valign = "center",
        rmargin = 6,
        bgimage = NEGConstants.iconShare,
        press = function()
            NEGRun.SetOfferShared(not NEGRun.IsOfferShared())
        end,
    }

    local offerPanel = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        tmargin = 6,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            shareButton,

            gui.Label{
                classes = { "sizeS" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                text = "Their Offer",
            },
        },

        offerLabel,
    }

    local tray = gui.Panel{
        classes = { "collapsed" },
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
    }

    local tracksPanel = gui.Panel{
        classes = { "collapsed" },
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }

    --No classes passed in: MCDMDivider copies the caller's options over its
    --own args, so a classes list here REPLACES {"mcdmDivider"} and the rule
    --loses the @border colour that makes it visible at all. Collapse it with
    --SetClass afterwards, which adds rather than replaces.
    local offerRule = gui.MCDMDivider{
        width = NEGConstants.sectionWidth,
        halign = "left",
        vmargin = 6,
    }
    offerRule:SetClass("collapsed", true)

    local tracksRule = gui.MCDMDivider{
        width = NEGConstants.sectionWidth,
        halign = "left",
        vmargin = 6,
    }
    tracksRule:SetClass("collapsed", true)

    local traitsPanel = gui.Panel{
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 6,
    }

    --Everything a player can be shown is behind an eye, so a table watching a
    --negotiation with everything closed needs telling that is deliberate.
    local watchingLabel = gui.Label{
        classes = { "sizeS", "noBold", "fgMuted", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        tmargin = 24,
        textAlignment = "center",
        textWrap = true,
        text = "The negotiation is under way.",
    }

    local workingColumn = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        statsRow,
        summaryPanel,
        scalesPanel,
        terminalLabel,
        offerPanel,
        offerRule,
        tray,
        tracksPanel,
        tracksRule,
        traitsPanel,
        watchingLabel,
    }

    --The NPC sits beside the board on the players' window: they are looking at
    --a person, not a form. The Director's window has no room for it and does
    --not need it - the NPC is named in the header. Neither these nor the
    --ending pane exist on the Director's window, so neither is built for it.
    local portrait
    local SetPortrait
    local portraitColumn
    local endingVerdict
    local endingOffer
    local endingPanel

    if not director then
        --Fills its column and takes its height from that width, so the 2:3 can
        --never push it outside the column it lives in. "image" keeps it
        --true-colour - the theme root tints a bare bgimage panel - and "bordered"
        --is the standard frame, so there is no hand-rolled border here.
        --Fills its column outright. The 2:3 comes from the column being two thirds
        --of the working area's height.
        portrait = gui.Panel{
            classes = { "image", "bordered" },
            interactable = false,
            width = "100%",
            height = "100%",
            halign = "left",
            valign = "top",
        }

        --The rulebook's twelve traits, read in the portrait's frame. All of
        --them, whatever has been revealed: it is the rules, not the NPC.
        local entries = {}
        for _, trait in ipairs(NEGRules.traits) do
            local parts = {
                "### " .. trait.text,
                "**Motivation:** " .. trait.motivation,
                "**Pitfall:** " .. trait.pitfall,
            }
            local bullets = {}
            for _, example in ipairs(trait.examples) do
                bullets[#bullets + 1] = "* <color=@fgMuted>" .. example .. "</color>"
            end
            parts[#parts + 1] = table.concat(bullets, "\n")
            entries[#entries + 1] = table.concat(parts, "\n\n")
        end

        local reference = gui.Panel{
            classes = { "bordered", "collapsed" },
            width = "100%",
            height = "100%",
            halign = "left",
            valign = "top",
            vscroll = true,

            gui.Label{
                classes = { "sizeXs", "noBold" },
                width = "100%-16",
                height = "auto",
                halign = "center",
                valign = "top",
                vmargin = 8,
                textWrap = true,
                markdown = true,
                text = ThemeEngine.ResolveTokens(table.concat(entries, "\n\n---\n\n")),
            },
        }

        --Per window: the board's rebuilds keep it, a fresh window starts on the NPC.
        local m_showReference = false
        local m_hasPortrait = false
        local referenceButton

        --Pure white on art; the lit glyph is a second panel so its class never fights an inline colour.
        local referenceIcon = gui.Panel{
            interactable = false,
            width = "70%",
            height = "70%",
            halign = "center",
            valign = "center",
            bgimage = NEGConstants.iconReference,
            bgcolor = "white",
        }
        local referenceIconLit = gui.Panel{
            classes = { "bgSuccess", "collapsed" },
            interactable = false,
            width = "70%",
            height = "70%",
            halign = "center",
            valign = "center",
            bgimage = NEGConstants.iconReference,
        }

        --- The NPC or the reference in the frame. With no portrait there is
        --- nothing to swap back to, so the reference stays and the button goes.
        local function ApplyFrame()
            local showReference = m_showReference or not m_hasPortrait
            portrait:SetClass("collapsed", showReference)
            reference:SetClass("collapsed", not showReference)
            referenceButton:SetClass("collapsed", not m_hasPortrait)
            referenceIcon:SetClass("collapsed", m_showReference)
            referenceIconLit:SetClass("collapsed", not m_showReference)
        end

        --- @param portraitid string
        SetPortrait = function(portraitid)
            m_hasPortrait = portraitid ~= ""
            if m_hasPortrait then
                portrait.bgimage = portraitid
            end
            ApplyFrame()
        end

        --A dark disc keeps the glyph legible over any portrait, black in every theme because it sits on art.
        referenceButton = gui.Panel{
            classes = { "collapsed" },
            floating = true,
            width = NEGConstants.referenceButtonSize,
            height = NEGConstants.referenceButtonSize,
            halign = "right",
            valign = "top",
            hmargin = 6,
            vmargin = 6,
            bgimage = true,
            bgcolor = NEGConstants.referenceScrim,
            cornerRadius = NEGConstants.referenceButtonSize / 2,
            hover = THCWidgets.Tooltip("Motivations and pitfalls"),
            press = function()
                m_showReference = not m_showReference
                ApplyFrame()
            end,

            referenceIcon,
            referenceIconLit,
        }

        portraitColumn = gui.Panel{
            classes = { "collapsed" },
            width = NEGConstants.playerPortraitWidth,
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",
            rmargin = NEGConstants.playerPortraitGap,

            portrait,
            reference,
            referenceButton,
        }

        --Two panels on one line: the NPC at a fixed width, the form taking the
        --rest.
        endingVerdict = gui.Label{
            classes = { "sizeL" },
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            tmargin = 8,
            textWrap = true,
            text = "",
        }

        endingOffer = gui.Label{
            classes = { "sizeS", "noBold" },
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            tmargin = 6,
            textWrap = true,
            markdown = true,
            text = "",
        }

        --Shown to the table when the negotiation closes. The final offer is theirs
        --to read whatever was shared during play.
        endingPanel = gui.Panel{
            classes = { "collapsed" },
            width = "100% available",
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",

            gui.Label{
                classes = { "sizeL" },
                width = "98%",
                height = "auto",
                halign = "left",
                valign = "top",
                text = "The negotiation is over.",
            },

            endingVerdict,

            gui.MCDMDivider{
                width = NEGConstants.sectionWidth,
                halign = "left",
                vmargin = 10,
            },

            gui.Label{
                classes = { "sizeS" },
                width = "98%",
                height = "auto",
                halign = "left",
                valign = "top",
                tmargin = 16,
                text = "Their Final Offer",
            },

            endingOffer,
        }
    end

    local liveBody
    if director then
        liveBody = workingColumn
    else
        workingColumn.selfStyle.width = "100% available"
        workingColumn.selfStyle.height = "100%"

        liveBody = gui.Panel{
            width = "100%",
            height = "100%",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            portraitColumn,
            workingColumn,
            endingPanel,
        }
    end

    local idleNotice = THCWidgets.Notice("No negotiation is running.")

    --- @param live NEGLive
    --- @return Panel[]
    local function BuildScales(live)
        local interest = live.interest
        local patience = live.patience
        local devil = live:try_get("devilInterest", false)
        local interestMax = live:InterestMax()

        --Both the caption and the tone read the halved track: what a devil's
        --Interest currently buys, not how many bubbles are lit.
        local resultInterest = live:ResultInterest()
        local interestCaption, interestClass = NEGWidgets.InterestCaption(resultInterest)

        if director then
            return {
                NEGWidgets.Scale{
                    which = NEGConstants.scaleInterest,
                    label = "Interest",
                    value = interest,
                    pipMax = interestMax,
                    toneValue = resultInterest,
                    interactive = true,
                    caption = interestCaption,
                    captionClass = interestClass,
                    change = function(value)
                        NEGRun.SetScale(NEGConstants.scaleInterest, value)
                    end,
                    eye = {
                        shown = live:try_get("showInterest", false),
                        change = function(shown)
                            NEGRun.SetRevealed(NEGConstants.scaleInterest, shown)
                        end,
                    },
                    trailing = gui.Panel{
                        classes = { cond(devil, "bgDanger", "bgFgMuted") },
                        width = 14,
                        height = 14,
                        halign = "left",
                        valign = "center",
                        lmargin = 4,
                        bgimage = NEGConstants.iconDevil,
                        hover = THCWidgets.Tooltip(cond(devil,
                            "Devil's bargain: Interest runs to 10 and is halved to name the offer. Click for a normal track.",
                            "Normal Interest. Click for a devil's doubled track.")),
                        press = function()
                            NEGRun.SetDevilInterest(not devil)
                        end,
                    },
                },

                NEGWidgets.Scale{
                    which = NEGConstants.scalePatience,
                    label = "Patience",
                    value = patience,
                    interactive = true,
                    change = function(value)
                        NEGRun.SetScale(NEGConstants.scalePatience, value)
                    end,
                    eye = {
                        shown = live:try_get("showPatience", false),
                        change = function(shown)
                            NEGRun.SetRevealed(NEGConstants.scalePatience, shown)
                        end,
                    },
                },
            }
        end

        --A closed scale keeps its bubbles and turns them to question marks.
        local wideOpen = live:try_get("open", false)
        local interestOpen = wideOpen or live:try_get("showInterest", false)
        local patienceOpen = wideOpen or live:try_get("showPatience", false)

        return {
            NEGWidgets.Scale{
                which = NEGConstants.scaleInterest,
                label = "Interest",
                value = interest,
                pipMax = interestMax,
                toneValue = resultInterest,
                interactive = false,
                unknown = not interestOpen,
                caption = cond(interestOpen, interestCaption, ""),
                captionClass = interestClass,
            },

            NEGWidgets.Scale{
                which = NEGConstants.scalePatience,
                label = "Patience",
                value = patience,
                interactive = false,
                unknown = not patienceOpen,
            },
        }
    end

    --- How many trait rows a player is allowed to see.
    --- @param live NEGLive
    --- @return number
    local function RevealedTraitCount(live)
        local count = 0
        for _, kind in ipairs({ "motivations", "pitfalls" }) do
            for _, entry in ipairs(NEGRun.Traits(live, kind)) do
                if entry.revealed then
                    count = count + 1
                end
            end
        end
        return count
    end

    local body
    --The table's board does not scroll: it is a thing to glance at, and a
    --scroll bar means somebody is missing half of it. The Director's does,
    --because their side carries the whole negotiation.
    body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vscroll = director,

        negotiationChanged = function(element)
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local live = NEGRun.Active()

            --A negotiation still in setup has not started.
            if live == nil then
                liveBody:SetClass("collapsed", true)
                idleNotice:SetClass("collapsed", false)
                return
            end

            local status = live:try_get("status")
            local onStage = director or status ~= NEGConstants.statusSetup

            liveBody:SetClass("collapsed", not onStage)
            idleNotice:SetClass("collapsed", onStage)

            if not onStage then
                return
            end

            --A closed negotiation gives the table its final offer and nothing
            --else to fiddle with.
            local finished = not director and status == NEGConstants.statusEnded
            if not director then
                endingPanel:SetClass("collapsed", not finished)
                workingColumn:SetClass("collapsed", finished)
            end

            local def = live:Definition()

            --The NPC stays beside the board for the whole negotiation, the
            --ending included: the table is looking at a person, not a form.
            --Set BEFORE the ending's early return, which otherwise leaves a
            --freshly built window - a reload, or a re-present after the
            --negotiation closed - with the portrait still collapsed.
            if not director then
                portraitColumn:SetClass("collapsed", false)

                SetPortrait(def ~= nil and def:try_get("portraitid", "") or "")
            end

            if finished then
                --Halved for a devil: the ladder is always read 0..5.
                local value = live:ResultInterest()
                --Only the tone is wanted here. InterestCaption's text is
                --"N  <offer name>", so its remainder past the number IS the
                --offer name, and pairing the two said it twice.
                local _, captionClass = NEGWidgets.InterestCaption(value)

                endingVerdict:SetClass("danger", captionClass == "danger")
                endingVerdict:SetClass("warning", captionClass == "warning")
                endingVerdict:SetClass("success", captionClass == "success")
                endingVerdict.text = NEGRules.OfferName(value)
                endingOffer.text = live:OfferText()
                return
            end

            local langid = def ~= nil and def:try_get("languageId", "") or ""

            statsRow:SetClass("collapsed", not director)
            summaryPanel:SetClass("collapsed", false)
            offerPanel:SetClass("collapsed", false)


            local summary = def ~= nil and def:try_get("summary", "") or ""
            summaryLabel.text = summary
            summaryPanel:SetClass("collapsed", trim(summary) == "")

            local wideOpen = live:try_get("open", false)
            local shared = wideOpen or live:try_get("offerShared", false)
            shareButton:SetClass("collapsed", not director)
            shareButton:SetClass("bgAccent", director and shared)
            shareButton:SetClass("bgFgPending", director and not shared)

            --The label stands either way, so the table knows an offer exists
            --and is being held back rather than that there is none.
            offerLabel.text = cond(director or shared, live:OfferText(), "")

            openCheck.value = wideOpen

            if director then
                local impression = NEGConstants.impressionDefault
                if def ~= nil then
                    impression = def:try_get("impression", impression)
                end
                impressionLabel.text = NEGRules.ImpressionText(impression)

                local language = NEGRules.LanguageName(langid)
                languageLabel.text = cond(language ~= "", language, "None set")
            end

            local scales = BuildScales(live)
            scalesPanel.children = scales

            local reason = live:TerminalReason()
            terminalLabel:SetClass("collapsed", not director or reason == "")
            terminalLabel:SetClass("warning", reason ~= "")
            terminalLabel.text = reason

            --The floor stands on both windows; the widgets decide whose token
            --this client may pick up.
            offerRule:SetClass("collapsed", false)
            tray:SetClass("collapsed", false)
            tracksPanel:SetClass("collapsed", false)
            tracksRule:SetClass("collapsed", false)

            tray.children = {
                NEGWidgets.Tray(NEGRun.FreeHeroes(live), function(charid)
                    NEGRun.Flow(NEGConstants.trackArgument):Return(charid)
                    NEGRun.Flow(NEGConstants.trackLearn):Return(charid)
                end),
            }

            tracksPanel.children = {
                TrackPanel(live, {
                    track = NEGConstants.trackArgument,
                    title = "Make Argument",
                    width = NEGConstants.trackArgumentWidth,
                    director = director,
                    slots = {
                        { key = THCRollFlow.slotLead, label = "Lead" },
                        { key = THCRollFlow.slotAssist, label = "Assist" },
                    },
                }),

                TrackPanel(live, {
                    track = NEGConstants.trackLearn,
                    title = "Learn Motivation / Pitfall",
                    width = NEGConstants.trackLearnWidth,
                    director = director,
                    slots = {
                        { key = THCRollFlow.slotLead, label = "Reader" },
                    },
                }),
            }

            traitsPanel.children = {
                TraitColumn(live, "motivations", "Motivations", director),
                TraitColumn(live, "pitfalls", "Pitfalls", director),
            }

            watchingLabel:SetClass("collapsed", true)
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        liveBody,
        idleNotice,
    }

    return { body = body }
end
