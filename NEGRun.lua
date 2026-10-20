local mod = dmhub.GetModLoading()

--- One hero at the table. Who is present decides the language patience bonus.
--- @class NEGParticipant
--- @field charid string
--- @field name string
--- @field included boolean
NEGParticipant = RegisterGameType("NEGParticipant")

NEGParticipant.name = ""
NEGParticipant.included = true

--- Absent on every participant stored before companions were carried, so both
--- default rather than being read with try_get at each site.
NEGParticipant.isCompanion = false
NEGParticipant.summonerId = ""

--- @param args nil|table
--- @return NEGParticipant
function NEGParticipant.CreateNew(args)
    return NEGParticipant.new(args or {})
end

--- A negotiation in play. Holds its own copy of the definition, so editing the
--- prepared version mid-run does not disturb it.
--- @class NEGLive
--- @field defid string what it was started from, for the library's play marker
--- @field def NEGDefinition a copy, never the library's object
--- @field interest number
--- @field patience number
--- @field showInterest boolean whether the table sees the interest scale
--- @field showPatience boolean whether the table sees the patience scale
--- @field languageBonus number patience granted for speaking their tongue
--- @field languageSpeakers string[] the heroes who earned it
--- @field revealedTraits table<string, boolean> trait rows the table has seen
--- @field status string
--- @field presented boolean whether the board is on the players' screens
NEGLive = RegisterGameType("NEGLive")

NEGLive.interest = 2
NEGLive.patience = 3
--- Copied from the definition at setup and toggleable from the board. Declared
--- so a negotiation started before devils existed reads false rather than
--- raising.
NEGLive.devilInterest = false

NEGLive.showInterest = false
NEGLive.showPatience = false
NEGLive.languageBonus = 0
NEGLive.status = NEGConstants.statusRunning
NEGLive.presented = false

--- Declared on the type so a document mutation can read them as plain fields
--- rather than through accessors that raise mid-transaction. Writers copy
--- before assigning, so these shared defaults are never written into.
NEGLive.revealedTraits = {}
NEGLive.participants = {}

--- Each track's roll lives in a THCRollFlow record of its own: `live.argument`
--- (Lead and Assist) and `live.learn` (the reader, in the Lead slot). On top of
--- the shared shape a record carries `accepted`, once the Director has taken
--- the Lead's roll, and `outcome` {text, interest, patience}. Neither field is
--- declared here: the flow writes into its record in place, and a shared
--- default would take those writes instead of the document.

--- Legacy: where a negotiation started before the tracks had records kept its
--- seats and rolls. Declared so an old document still reads; MigrateLive moves
--- them onto the records and empties them.
NEGLive.slots = {}
NEGLive.resolution = nil
NEGLive.assistTier = 0
NEGLive.rolls = {}

--- Whether the argument appeals to a motivation. Never sent to the roller;
--- decides which outcome ladder the returned tier is read against.
NEGLive.appealMotivation = false

--- Heroes who have taken a test since the floor last turned over. The set
--- clears once everyone is in it.
NEGLive.acted = {}

--- Whether the table can currently see the NPC's offer. Cleared whenever
--- interest moves, because the offer moved with it.
NEGLive.offerShared = false

--- Run the negotiation in the open: the table sees both scales, the offer, and
--- the real tier ladders on their roll dialogs. Motivations and pitfalls are
--- unaffected and stay behind their own eyes.
NEGLive.open = false

--- Set when the Director clears a read of the room, cleared when an argument
--- is made. The rules bar a second read until then.
NEGLive.learnLocked = false

--- Whether the Assist seat is kept off the players' board. A standing choice
--- for the whole negotiation, not per argument, so clearing a track leaves it
--- where the Director put it.
NEGLive.assistHidden = false

--- The journal page that launched this, so ending it can tick that Run row.
NEGLive.launchedFromDocid = ""

--- Every resolved argument, read and pitfall, in order. The slots and rolls
--- are cleared for the next argument, so this is the only thing that remembers
--- the negotiation happened. In memory with the Run; nothing is written out.
--- @type {kind: string, tier: number|nil, motivation: boolean, traitId: string|nil,
---        lead: string|nil, assist: string|nil, reader: string|nil,
---        interestDelta: number, patienceDelta: number}[]
NEGLive.history = {}

--- The frozen closing report, built once when the negotiation ends.
NEGLive.ending = nil

--- Legacy, as `slots` above.
NEGLive.assistPending = nil

--- Append one settled event to the Run's history. Runs INSIDE a mutation, on
--- the live it is handed; copies before writing so a Run that never got its
--- own table cannot write into the type's shared default.
--- @param live NEGLive
--- @param entry table
local function AppendHistory(live, entry)
    local history = {}
    for i, existing in ipairs(live.history) do
        history[i] = existing
    end
    history[#history + 1] = entry
    live.history = history
end

--- Heroes on the map, and their beastheart companions, in roster order: heroes
--- by name with each companion tucked in directly behind its owner.
---
--- On the map only. The engine's prompt gate tests
--- `dmhub.GetTokenById(tokid) ~= nil` OUTSIDE its forceuserid disjunct
--- (Draw Steel UI/DSRequestRollsDialog.lua), and that call is loaded-map only,
--- so an off-map hero cannot be asked to roll by any means.
---
--- Companions are carried but are not a roster choice: they follow their hero.
--- @return NEGParticipant[]
function NEGLive.EligibleParticipants()
    local roster = THCUtils.PartyRoster{ placedOnly = true, includeCompanions = true }

    local owned = {}
    local heroes = {}

    for _, entry in ipairs(roster) do
        local participant = NEGParticipant.CreateNew{
            charid = entry.charid,
            name = entry.name,
            isCompanion = entry.isCompanion,
            summonerId = entry.summonerId or "",
            included = true,
        }

        if entry.isCompanion then
            local owner = entry.summonerId or ""
            owned[owner] = owned[owner] or {}
            table.insert(owned[owner], participant)
        else
            heroes[#heroes + 1] = participant
        end
    end

    table.sort(heroes, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    --Spliced after the sort, so a companion cannot be pulled away from its hero
    --by its own name. A companion whose owner did not make the roster is
    --dropped with it: it is only ever here on that hero's account.
    local result = {}
    for _, participant in ipairs(heroes) do
        result[#result + 1] = participant
        for _, companion in ipairs(owned[participant.charid] or {}) do
            result[#result + 1] = companion
        end
    end

    return result
end

--- A negotiation ready to be set up. The language bonus is applied at Start,
--- once the roster is settled.
--- @param def NEGDefinition
--- @return NEGLive
function NEGLive.FromDefinition(def)
    return NEGLive.new{
        defid = def:GetID(),
        def = DeepCopy(def),
        revealedTraits = {},
        participants = NEGLive.EligibleParticipants(),
        interest = NEGConstants.Clamp(def:try_get("interest", NEGDefinition.interest),
            NEGConstants.scaleMin,
            NEGRules.InterestMax(def:try_get("devilInterest", false))),
        patience = NEGConstants.Clamp(def:try_get("patience", NEGDefinition.patience),
            NEGConstants.scaleMin, NEGConstants.scaleMax),
        languageBonus = 0,
        languageSpeakers = {},
        devilInterest = def:try_get("devilInterest", false),
        showInterest = def:try_get("showInterest", false),
        showPatience = def:try_get("showPatience", false),
        status = NEGConstants.statusSetup,
        presented = false,
        argument = THCRollFlow.NewRecord(),
        learn = THCRollFlow.NewRecord(),
    }
end

--- The charids of the heroes actually taking part.
--- @return string[]
function NEGLive:IncludedCharids()
    local included = {}
    for _, p in ipairs(self:try_get("participants", {})) do
        if p:try_get("included", true) and not p.isCompanion then
            included[p.charid] = true
        end
    end

    local result = {}
    for _, p in ipairs(self:try_get("participants", {})) do
        --A companion is never ticked or unticked in its own right; it takes
        --part exactly when the hero it belongs to does.
        local taking = p:try_get("included", true)
        if p.isCompanion then
            taking = included[p.summonerId] == true
        end

        if taking then
            result[#result + 1] = p.charid
        end
    end
    return result
end

--- @return NEGDefinition|nil
function NEGLive:Definition()
    return self:try_get("def")
end

--- @return string
function NEGLive:Name()
    local def = self:Definition()
    return def ~= nil and def:try_get("name", "") or ""
end

--- @return string
function NEGLive:NpcName()
    local def = self:Definition()
    return def ~= nil and def:try_get("npcName", "") or ""
end

--- What the NPC is offering right now, in the Director's own words. Falls back
--- to the rulebook's shape of answer when nothing was written for this score.
--- @return string
function NEGLive:OfferText()
    local def = self:Definition()
    local written = def ~= nil and def:GetOffer(self.interest) or ""
    if trim(written) ~= "" then
        return written
    end
    return NEGRules.OfferDetail(self.interest)
end

--- A negotiation ends of its own accord at either end of the interest scale or
--- when patience runs out. The Director is told, and closes it themself.
--- @return boolean
function NEGLive:AtTerminal()
    return self.interest <= NEGConstants.scaleMin
        or self.interest >= self:InterestMax()
        or self.patience <= NEGConstants.scaleMin
end

--- The top of this negotiation's Interest track: 10 for a devil, 5 otherwise.
--- @return number
function NEGLive:InterestMax()
    return NEGRules.InterestMax(self:try_get("devilInterest", false))
end

--- The 0..5 its offer ladder is read with, halved for a devil.
--- @return number
function NEGLive:ResultInterest()
    return NEGRules.ResultInterest(self.interest,
        self:try_get("devilInterest", false))
end

--- Why it is over, or an empty string while it is not.
--- @return string
function NEGLive:TerminalReason()
    if self.interest >= self:InterestMax() then
        return "Interest is full. This is their final offer."
    end
    if self.interest <= NEGConstants.scaleMin then
        return "Interest is gone. They will not deal."
    end
    if self.patience <= NEGConstants.scaleMin then
        return "Patience is spent. This is their final offer."
    end
    return ""
end

--- The one negotiation in play, and everything that moves it.
NEGRun = RegisterGameType("NEGRun")

mod:RegisterDocumentForCheckpointBackups(NEGConstants.activeRunDoc)

--- @return LuaCodeModDocumentSnapshot
function NEGRun.Doc()
    return mod:GetDocumentSnapshot(NEGConstants.activeRunDoc)
end

--- @return string monitorGame path for the live negotiation
function NEGRun.DocPath()
    return mod:GetDocumentPath(NEGConstants.activeRunDoc)
end

--- @param description string
--- @param fn fun(doc: table)
function NEGRun.Mutate(description, fn)
    local doc = NEGRun.Doc()
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description)
end

--- @return NEGLive|nil
function NEGRun.Active()
    local doc = NEGRun.Doc()
    if doc == nil or doc.data == nil then
        return nil
    end
    return doc.data.live
end

--- The live negotiation, if it came from this prepared one.
--- @param defid string
--- @return NEGLive|nil
function NEGRun.ActiveFor(defid)
    local live = NEGRun.Active()
    if live ~= nil and live:try_get("defid") == defid then
        return live
    end
    return nil
end

--- Open a prepared negotiation's setup step. One negotiation at a time.
--- @param defid string
--- @param docid nil|string the journal page that launched it
--- @return boolean whether it opened
function NEGRun.BeginSetup(defid, docid)
    if NEGRun.Active() ~= nil then
        return false
    end

    local def = NEGDefinition.GetByID(defid)
    if def == nil then
        return false
    end

    local live = NEGLive.FromDefinition(def)
    live.launchedFromDocid = docid or ""

    NEGRun.Mutate("Begin negotiation setup", function(data)
        data.live = live
    end)

    --The table gets the backdrop over everything while the Director sets up;
    --the Director is left looking at the map, since "players" excludes them.
    THCUtils.ShowScene(def:try_get("image", ""), true, false)

    return true
end

--- Tick the Run row for the page that launched this negotiation, if it came
--- from one. RunAgenda loads late, hence the rawget.
--- @param docid string
local function MarkRunItemDone(docid)
    local agenda = rawget(_G, "RunAgenda")
    if agenda == nil or docid == nil or docid == "" then
        return
    end

    local items = agenda.GetItems()
    local touched = false

    for _, item in ipairs(items) do
        if item.docid == docid and item.done ~= true then
            item.done = true
            touched = true
        end
    end

    if touched then
        agenda.SetItems(items, "Negotiation complete")
    end
end

--- @param charid string
--- @param included boolean
function NEGRun.SetParticipantIncluded(charid, included)
    NEGRun.Mutate("Change negotiation roster", function(data)
        local live = data.live
        if live == nil then
            return
        end
        for _, p in ipairs(live.participants) do
            if p.charid == charid then
                p.included = included
                return
            end
        end
    end)
end

--- What the current roster would open on.
--- @param live NEGLive
--- @return number patience
--- @return number bonus
--- @return string[] speakers
function NEGRun.PreviewOpening(live)
    local def = live:Definition()
    return NEGRules.OpeningPatience(
        live.patience,
        def ~= nil and def:try_get("languageId", "") or "",
        live:IncludedCharids())
end

--- Open the negotiation, banking the language patience bonus.
function NEGRun.Start()
    local live = NEGRun.Active()
    if live == nil then
        return
    end

    local patience, bonus, speakers = NEGRun.PreviewOpening(live)

    NEGRun.Mutate("Start negotiation", function(data)
        local target = data.live
        if target == nil then
            return
        end
        target.status = NEGConstants.statusRunning
        target.patience = patience
        target.languageBonus = bonus
        target.languageSpeakers = speakers
    end)

    --Play begins, so the backdrop drops behind the interface and the Director
    --joins the table in seeing it. After the mutate: one document at a time.
    local def = live:Definition()
    if def ~= nil then
        THCUtils.ShowScene(def:try_get("image", ""), "all", true)
    end
end

--- Back to setup, scales restored to what the negotiation was prepared with.
function NEGRun.Reset()
    local live = NEGRun.Active()
    if live == nil then
        return
    end

    local def = live:Definition()
    local interest = def ~= nil
        and def:try_get("interest", NEGDefinition.interest)
        or NEGDefinition.interest
    local patience = def ~= nil
        and def:try_get("patience", NEGDefinition.patience)
        or NEGDefinition.patience

    NEGRun.AbandonRolls()

    NEGRun.Mutate("Reset negotiation", function(data)
        local target = data.live
        if target == nil then
            return
        end
        target.status = NEGConstants.statusSetup
        target.interest = interest
        target.patience = patience
        target.languageBonus = 0
        target.languageSpeakers = {}
        target.revealedTraits = {}
        target.presented = false
    end)

    GameHud.HidePresentedDialog()
end

--- Abandon a negotiation that has not started.
function NEGRun.Discard()
    NEGRun.Mutate("Cancel negotiation", function(data)
        data.live = nil
    end)
    GameHud.HidePresentedDialog()
end

--- @param which string NEGConstants.scaleInterest or scalePatience
--- @param value number
function NEGRun.SetScale(which, value)
    NEGRun.Mutate("Set negotiation scale", function(data)
        local live = data.live
        if live == nil then
            return
        end
        --Only Interest grows for a devil; patience keeps its own five.
        local top = NEGConstants.scaleMax
        if which == NEGConstants.scaleInterest then
            top = live:InterestMax()
        end
        live[which] = NEGConstants.Clamp(value, NEGConstants.scaleMin, top)

        --Interest moved, so the shared offer is now the wrong one.
        if which == NEGConstants.scaleInterest then
            live.offerShared = false
        end
    end)
end

--- @param shared boolean
function NEGRun.SetOfferShared(shared)
    NEGRun.Mutate("Share negotiation offer", function(data)
        local live = data.live
        if live ~= nil then
            live.offerShared = shared
        end
    end)
end

--- @return boolean
function NEGRun.IsOfferShared()
    local live = NEGRun.Active()
    return live ~= nil and live:try_get("offerShared", false)
end

--- @param track string
--- @return string the other track
local function OtherTrack(track)
    return cond(track == NEGConstants.trackArgument, NEGConstants.trackLearn, NEGConstants.trackArgument)
end

--- A track's roll record as it stands, or nil when there is no negotiation.
--- One not yet made reads as empty.
--- @param live NEGLive|nil
--- @param track string
--- @return table|nil
function NEGRun.Record(live, track)
    if live == nil then
        return nil
    end
    return live:try_get(track) or THCRollFlow.NewRecord()
end

--- Whether a negotiation still keeps its seats and rolls the old way, waiting
--- for the Director's client to move them onto the records.
--- @param live NEGLive
--- @return boolean
local function HasLegacy(live)
    return live:try_get("resolution") ~= nil
        or next(live:try_get("slots", {})) ~= nil
        or next(live:try_get("rolls", {})) ~= nil
        or live:try_get("assistTier", 0) ~= 0
end

--- Every hero at the table who is not already standing in a seat, each
--- carrying whether they have already taken a test this time around.
--- @param live NEGLive
--- @return {charid: string, name: string, acted: boolean}[]
function NEGRun.FreeHeroes(live)
    local taken = {}
    for _, track in ipairs{ NEGConstants.trackArgument, NEGConstants.trackLearn } do
        for _, entry in pairs(NEGRun.Record(live, track).slots) do
            if entry.charid ~= nil then
                taken[entry.charid] = true
            end
        end
    end

    local acted = live:try_get("acted", {})

    local result = {}
    for _, p in ipairs(live:try_get("participants", {})) do
        local charid = p.charid
        if p:try_get("included", true) and taken[charid] ~= true then
            result[#result + 1] = {
                charid = charid,
                name = p:try_get("name", ""),
                acted = acted[charid] == true,
            }
        end
    end
    return result
end

--- Take one track off the floor: its heroes go back to the tray marked spent
--- and its record starts over. Once everyone is spent the set clears, turning
--- the round over. Runs INSIDE a document mutation, on the live it is handed.
--- @param live NEGLive
--- @param track string
local function ClearTrack(live, track)
    local acted = {}
    for key, value in pairs(live.acted) do
        acted[key] = value
    end

    for _, entry in pairs(NEGRun.Record(live, track).slots) do
        if entry.charid ~= nil then
            acted[entry.charid] = true
        end
    end

    --Everyone spent means nobody is.
    local anyFresh = false
    for _, p in ipairs(live.participants) do
        if p.included ~= false and acted[p.charid] ~= true then
            anyFresh = true
        end
    end
    if not anyFresh then
        acted = {}
    end

    live.acted = acted
    live[track] = THCRollFlow.NewRecord()

    --Clearing a read locks it; clearing an argument is what frees it again.
    if track == NEGConstants.trackArgument then
        live.appealMotivation = false
        live.learnLocked = false
    else
        live.learnLocked = true
    end
end

--- Clear one track for the next argument, dropping any roll still out on it.
--- @param track string
function NEGRun.ResetTrack(track)
    NEGRun.Flow(track):Abandon()
    NEGRun.Mutate("Reset negotiation track", function(data)
        local live = data.live
        if live == nil then
            return
        end
        ClearTrack(live, track)
    end)
end

--- Whether patience is spent, which ends every roll.
--- @param live NEGLive
--- @return boolean
local function Expired(live)
    return live.patience <= NEGConstants.scaleMin
end

--- Whether a track's seats may change hands: nothing out, nothing rolled,
--- nothing taken, and the track itself open.
--- @param live NEGLive|nil
--- @param track string
--- @return boolean
function NEGRun.CanStage(live, track)
    if live == nil or live:try_get("status") ~= NEGConstants.statusRunning or Expired(live) then
        return false
    end
    if track == NEGConstants.trackLearn and live:try_get("learnLocked", false) then
        return false
    end
    local record = NEGRun.Record(live, track)
    return record.pending == nil and next(record.rolls) == nil and record.accepted ~= true
end

--- The roll flow over one track's record. Cheap: make one whenever needed.
---
--- Writes refuse while the negotiation still keeps the old shape, so nothing
--- lands in a record before the Director's client has moved the old seats in.
--- @param track string
--- @return THCRollFlow
function NEGRun.Flow(track)
    local other = OtherTrack(track)

    --The live being changed, while inside one of this flow's changes, so the
    --one-hero rule can reach the other track in the same change.
    local m_live = nil

    return THCRollFlow.CreateNew{
        read = function()
            return NEGRun.Record(NEGRun.Active(), track)
        end,

        mutate = function(description, fn)
            NEGRun.Mutate(description, function(data)
                local live = data.live
                if live == nil or HasLegacy(live) then
                    return
                end
                local record = live:try_get(track)
                local created = record == nil
                if created then
                    record = THCRollFlow.NewRecord()
                end
                m_live = live
                fn(record)
                m_live = nil
                if created then
                    live[track] = record
                end
            end)
        end,

        checkId = NEGConstants.rollCheckId,
        characteristics = function()
            return NEGConstants.argumentAttributes
        end,
        skills = function()
            return {}
        end,
        anySkill = true,

        title = function()
            return cond(track == NEGConstants.trackLearn, "Read the room", "Make an argument")
        end,

        leadTiers = function()
            local live = NEGRun.Active()
            return live ~= nil and NEGRun.LeadTiers(live, track) or {}
        end,

        canStage = function()
            return NEGRun.CanStage(NEGRun.Active(), track)
        end,

        --A seat's picks stay open until that seat rolls.
        canEdit = function(slot)
            local live = NEGRun.Active()
            if live == nil or live:try_get("status") ~= NEGConstants.statusRunning or Expired(live) then
                return false
            end
            local record = NEGRun.Record(live, track)
            return record.pending == nil and record.rolls[slot] == nil and record.accepted ~= true
        end,

        canRoll = function()
            local live = NEGRun.Active()
            return live ~= nil and live:try_get("status") == NEGConstants.statusRunning
                and not Expired(live) and NEGRun.Record(live, track).accepted ~= true
        end,

        --One roll out across both tracks.
        sendBlocker = function()
            if NEGRun.Record(NEGRun.Active(), other).pending ~= nil then
                return "Waiting on the other track's roll."
            end
            return nil
        end,

        --A hero already rolling or rolled on the other track stays there.
        mayPlace = function(charid)
            local record = NEGRun.Record(NEGRun.Active(), other)
            for slot, entry in pairs(record.slots) do
                if entry.charid == charid then
                    return record.pending == nil and record.rolls[slot] == nil
                end
            end
            return true
        end,

        release = function(charid)
            if m_live == nil then
                return
            end
            local record = m_live:try_get(other)
            if record == nil then
                return
            end
            for slot, entry in pairs(record.slots) do
                if entry.charid == charid then
                    record.slots[slot] = nil
                end
            end
        end,

        --Carried on the seat, so each roller answers only for their own Renown.
        decorateInfo = function(slot, info, assignment, entry)
            info.renownEdge = entry ~= nil and entry.renownEdge == true
        end,
    }
end

--- @param value boolean
function NEGRun.SetOpen(value)
    NEGRun.Mutate("Set negotiation openness", function(data)
        if data.live ~= nil then
            data.live.open = value
        end
    end)
end

--- Turn the devil's doubled Interest track on or off mid-run. The live value is
--- converted with it - doubled on, halved off - so what the table had earned
--- reads the same before and after.
--- @param devil boolean
function NEGRun.SetDevilInterest(devil)
    NEGRun.Mutate("Set devil interest", function(data)
        local live = data.live
        if live == nil or live:try_get("devilInterest", false) == (devil == true) then
            return
        end
        live.devilInterest = devil == true
        live.interest = NEGRules.ConvertInterest(live.interest, devil == true)
        live.offerShared = false
    end)
end

--- @param hidden boolean
function NEGRun.SetAssistHidden(hidden)
    NEGRun.Mutate("Show or hide the assist", function(data)
        if data.live ~= nil then
            data.live.assistHidden = hidden == true
        end
    end)
end

--- @return boolean
function NEGRun.IsOpen()
    local live = NEGRun.Active()
    return live ~= nil and live:try_get("open", false)
end

--- @param value boolean
function NEGRun.SetAppealMotivation(value)
    NEGRun.Mutate("Set negotiation appeal", function(data)
        if data.live ~= nil then
            data.live.appealMotivation = value
        end
    end)
end

--- @param which string
--- @param delta number
function NEGRun.AdjustScale(which, delta)
    local live = NEGRun.Active()
    if live == nil then
        return
    end
    NEGRun.SetScale(which, live[which] + delta)
end

--- Show or hide one scale to the table.
--- @param which string
--- @param shown boolean
function NEGRun.SetRevealed(which, shown)
    local key = cond(which == NEGConstants.scaleInterest, "showInterest", "showPatience")
    NEGRun.Mutate("Reveal negotiation scale", function(data)
        local live = data.live
        if live ~= nil then
            live[key] = shown
        end
    end)
end

--- @param which string
--- @return boolean
function NEGRun.IsRevealed(which)
    local live = NEGRun.Active()
    if live == nil then
        return false
    end
    if which == NEGConstants.scaleInterest then
        return live:try_get("showInterest", false)
    end
    return live:try_get("showPatience", false)
end

--- Motivations or pitfalls, alphabetical, each with its revealed state.
--- @param live NEGLive
--- @param kind string "motivations" or "pitfalls"
--- @return {id: string, trait: string, name: string, note: string, revealed: boolean}[]
function NEGRun.Traits(live, kind)
    local def = live ~= nil and live:Definition() or nil
    if def == nil then
        return {}
    end

    local revealed = live:try_get("revealedTraits", {})
    local result = {}

    for _, row in ipairs(def:try_get(kind, {})) do
        local trait = row:try_get("trait", "")
        result[#result + 1] = {
            id = row.id,
            trait = trait,
            name = NEGRules.TraitName(trait),
            note = row:try_get("note", ""),
            revealed = revealed[row.id] == true,
        }
    end

    table.sort(result, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return result
end

--- Show or hide one motivation or pitfall to the table.
--- @param rowId string
--- @param shown boolean
function NEGRun.SetTraitRevealed(rowId, shown)
    NEGRun.Mutate("Reveal negotiation trait", function(data)
        local live = data.live
        if live == nil then
            return
        end
        --Copied before write: a live that never got its own table would
        --otherwise mutate the type's shared default.
        local revealed = {}
        for key, value in pairs(live.revealedTraits) do
            revealed[key] = value
        end
        revealed[rowId] = cond(shown, true, nil)
        live.revealedTraits = revealed
    end)
end

--- The heroes argued straight into one of the NPC's pitfalls. No test is
--- rolled: interest and patience each drop by 1, the pitfall opens to the table
--- so they can see what they trod on, and whoever was arguing goes back to the
--- tray spent.
--- @param rowId string the pitfall's NEGRun.Traits row id
function NEGRun.HitPitfall(rowId)
    local live = NEGRun.Active()
    if live == nil then
        return
    end

    --A pitfall is settled instead of a roll, so an argument already out with a
    --player is void. The request lives in the engine rather than the document,
    --so it has to be dropped before the mutation clears what names it.
    local flow = NEGRun.Flow(NEGConstants.trackArgument)
    flow:Abandon()
    local seats = flow:Effective()

    local outcome = NEGRules.PitfallOutcome()

    NEGRun.Mutate("Negotiation pitfall", function(data)
        local target = data.live
        if target == nil then
            return
        end

        --Copied before write: a live that never got its own table would
        --otherwise mutate the type's shared default.
        local revealed = {}
        for key, value in pairs(target.revealedTraits) do
            revealed[key] = value
        end
        revealed[rowId] = true
        target.revealedTraits = revealed

        target.interest = NEGConstants.Clamp(target.interest + outcome.interest,
            NEGConstants.scaleMin, target:InterestMax())
        target.patience = NEGConstants.Clamp(target.patience + outcome.patience,
            NEGConstants.scaleMin, NEGConstants.scaleMax)

        --Interest moved, so the offer moved with it.
        target.offerShared = false

        AppendHistory(target, {
            kind = "pitfall",
            motivation = false,
            traitId = rowId,
            lead = seats.lead ~= nil and seats.lead.charid or nil,
            assist = seats.assist ~= nil and seats.assist.charid or nil,
            interestDelta = outcome.interest,
            patienceDelta = outcome.patience,
        })

        ClearTrack(target, NEGConstants.trackArgument)
    end)

    printf("NEG:: pitfall %s - interest%+d patience%+d",
        tostring(rowId), outcome.interest, outcome.patience)
end

--- @return boolean
function NEGRun.IsPresented()
    local live = NEGRun.Active()
    return live ~= nil and live:try_get("presented", false)
end

--- @param hostPanel Panel the Director's window, which owns the presentation
function NEGRun.PresentToPlayers(hostPanel)
    NEGRun.Mutate("Show negotiation", function(data)
        if data.live ~= nil then
            data.live.presented = true
        end
    end)
    GameHud.PresentDialogToUsers(hostPanel, NEGConstants.dialogId, {})
end

function NEGRun.HideFromPlayers()
    NEGRun.Mutate("Hide negotiation", function(data)
        if data.live ~= nil then
            data.live.presented = false
        end
    end)
    GameHud.HidePresentedDialog()
end

--- Close the negotiation but leave it on screen, so the Director can read the
--- final offer out before clearing it away.
function NEGRun.End()
    local live = NEGRun.Active()
    NEGRun.AbandonRolls()

    --The board stays up: the table reads the final offer off it. Clear takes
    --it down.
    NEGRun.Mutate("End negotiation", function(data)
        if data.live ~= nil then
            data.live.status = NEGConstants.statusEnded

            --Frozen here: the report reads the history and the scales as they
            --stood at the close, and the Director may still move the pips
            --afterwards without rewriting what happened.
            data.live.ending = NEGRules.BuildEnding(data.live)
        end
    end)

    if live ~= nil then
        MarkRunItemDone(live:try_get("launchedFromDocid", ""))
    end
end

--- @param victories number
function NEGRun.SetEndingVictories(victories)
    local live = NEGRun.Active()
    local ending = live ~= nil and live:try_get("ending") or nil
    if ending == nil then
        return
    end

    local value = math.max(0, math.floor(victories or 0))
    if ending.victories == value then
        return
    end

    NEGRun.Mutate("Set Victory award", function(data)
        local e = data.live ~= nil and data.live:try_get("ending") or nil
        if e ~= nil then
            e.victories = value
        end
    end)
end

--- Hand the Victories out, once. SetVictories is an absolute write, so without
--- the flag a second press would award them all over again.
function NEGRun.AwardVictories()
    local live = NEGRun.Active()
    local ending = live ~= nil and live:try_get("ending") or nil
    if ending == nil or ending.awarded == true then
        return
    end

    local amount = ending.victories or 0
    local awardedTo = {}

    for _, charid in ipairs(live:IncludedCharids()) do
        local token = dmhub.GetCharacterById(charid)
        if token ~= nil then
            awardedTo[#awardedTo + 1] = NEGRun.ParticipantName(live, charid)
            token:ModifyProperties{
                description = "Award Victories",
                combine = true,
                execute = function()
                    token.properties:SetVictories(token.properties:GetVictories() + amount)
                end,
            }
        end
    end

    NEGRun.Mutate("Award Victories", function(data)
        local e = data.live ~= nil and data.live:try_get("ending") or nil
        if e ~= nil then
            e.awarded = true
            e.awardedTo = awardedTo
        end
    end)
end

--- Who did what, for the celebration's cards.
--- @param live NEGLive
--- @return table[]
function NEGRun.BuildRecap(live)
    local rows = {}
    local byChar = {}

    for _, charid in ipairs(live:IncludedCharids()) do
        local row = {
            charid = charid,
            name = NEGRun.ParticipantName(live, charid),
            led = 0,
            assisted = 0,
            read = 0,
            bestTier = nil,
        }
        byChar[charid] = row
        rows[#rows + 1] = row
    end

    for _, entry in ipairs(live:try_get("history", {})) do
        --A pitfall is not an argument led: nobody rolled for it.
        if entry.kind ~= "pitfall" then
            local lead = entry.lead ~= nil and byChar[entry.lead] or nil
            if lead ~= nil then
                lead.led = lead.led + 1
                if entry.tier ~= nil
                    and (lead.bestTier == nil or entry.tier > lead.bestTier) then
                    lead.bestTier = entry.tier
                end
            end

            local assist = entry.assist ~= nil and byChar[entry.assist] or nil
            if assist ~= nil then
                assist.assisted = assist.assisted + 1
            end
        end

        local reader = entry.reader ~= nil and byChar[entry.reader] or nil
        if reader ~= nil then
            reader.read = reader.read + 1
        end
    end

    table.sort(rows, function(a, b)
        if a.led ~= b.led then
            return a.led > b.led
        end
        if a.assisted ~= b.assisted then
            return a.assisted > b.assisted
        end
        return string.lower(a.name) < string.lower(b.name)
    end)

    return rows
end

--- Everything the celebration needs, detached from the Run. The Run is cleared
--- the moment the report goes out, so the report cannot read it.
--- @param live NEGLive
--- @return table
function NEGRun.BuildReportPayload(live)
    --The ladder is read from the halved track, so a devil's 7 reports as a 3.
    local interest = live:ResultInterest()

    return {
        name = live:Name(),
        npcName = live:NpcName(),
        result = NEGRules.OfferName(interest),
        detail = live:OfferText(),
        interest = interest,
        patience = live.patience,
        ending = DeepCopy(live:try_get("ending", {})),
        recap = NEGRun.BuildRecap(live),
    }
end

--- Throw the NPC's name across every screen with the sword reveal, so the
--- report arrives as an event rather than a window appearing.
--- @param payload table
function NEGRun.AnnounceEnding(payload)
    local subtitle = payload.result
    local victories = payload.ending ~= nil and payload.ending.victories or 0
    if victories > 0 then
        subtitle = string.format("%s  -  %d %s", subtitle, victories,
            cond(victories == 1, "Victory", "Victories"))
    end

    DramaticBanner.Show{
        text = cond(payload.npcName ~= "", payload.npcName, payload.name),
        subtitle = subtitle,
    }
end

--- Send the celebration to every client, the Director included. It travels as
--- a payload rather than a pointer at the Run, so clearing the Run in the same
--- breath cannot empty it out from under the table.
--- @param payload table
function NEGRun.PresentReport(payload)
    GameHud.PresentDialogToUsers(GameHud.instance.parentPanel,
        NEGConstants.dialogId, { report = payload, ttl = NEGConstants.celebrationTTL })
end

--- The Director is done. Award, announce with the banner, clear the
--- negotiation, and let the celebration land as the banner draws off.
function NEGRun.CompleteRun()
    if NEGRun.Active() == nil then
        return
    end

    --Award before the snapshot, so the celebration carries who got what.
    NEGRun.AwardVictories()

    local live = NEGRun.Active()
    if live == nil then
        return
    end

    local payload = NEGRun.BuildReportPayload(live)

    NEGRun.AnnounceEnding(payload)
    NEGRun.Clear()
    LaunchablePanel.LaunchPanelByName(NEGConstants.panelName, "hide")

    dmhub.Schedule(DramaticBanner.holdTime, function()
        if mod.unloaded then
            return
        end
        NEGRun.PresentReport(payload)
    end)
end

--==============================================================================
-- ASKING A PLAYER TO ROLL
--==============================================================================

--- The player-facing roll. The assist's grant is THCRollFlow's; Renown is
--- ours. They stack: an assisted lead leaning on their Renown carries both.
THCRollFlow.RegisterCheck(NEGConstants.rollCheckId, NEGConstants.modifierRollType,
    function(check, creature, options, result)
        --Leaning on Renown is always an edge, so the wire carries only that it
        --is on.
        if check.info.renownEdge == true then
            local described = THCRoll.DescribeGrant(creature, options, "edge",
                "Renown",
                "You leaned on your Renown to make this argument, for an edge.",
                NEGConstants.modifierRollType)
            if described ~= nil then
                result[#result + 1] = described
            end
        end
    end)

--- What a Lead is shown before they roll. A read of the room always gets its
--- real ladder, which gives nothing away. An argument gets vague bands unless
--- the negotiation is open, because its real ladder is read against this
--- NPC's motivations and so leaks them.
--- @param live NEGLive
--- @param track string
--- @return string[]
function NEGRun.LeadTiers(live, track)
    if track == NEGConstants.trackLearn then
        return NEGRules.TierText(track, false)
    end
    if live:try_get("open", false) then
        return NEGRules.TierText(track, live:try_get("appealMotivation", false))
    end
    return DeepCopy(NEGConstants.tierBands)
end

--- What the Lead's roll comes to: as the Director took it, once taken, and
--- read off the roll before that.
--- @param live NEGLive
--- @param track string
--- @return nil|{text: string, interest: number, patience: number}
function NEGRun.Outcome(live, track)
    local record = NEGRun.Record(live, track)
    if record.outcome ~= nil then
        return record.outcome
    end
    local roll = record.rolls[THCRollFlow.slotLead]
    if roll == nil then
        return nil
    end
    if track == NEGConstants.trackLearn then
        return NEGRules.LearnOutcome(roll.tier or 1)
    end
    return NEGRules.ArgumentOutcome(roll.tier or 1,
        live:try_get("appealMotivation", false), roll.naturalRoll)
end

--- The tier table one viewer sees for a track. A read's outcomes give nothing
--- away; an argument's are read against this NPC's motivations, so they are
--- the Director's unless the negotiation is open. The tier itself is no
--- secret: the table sees the roll.
--- @param live NEGLive
--- @param track string
--- @param director boolean
--- @return {labels: string[]|nil, landed: number|nil}
function NEGRun.TierTable(live, track, director)
    local roll = NEGRun.Record(live, track).rolls[THCRollFlow.slotLead]
    local landed = THCRollFlow.LandedRow(roll, false)

    local labels = nil
    if track == NEGConstants.trackLearn then
        labels = {}
        for tier = 1, 3 do
            labels[tier] = NEGRules.LearnOutcome(tier).text
        end
    elseif director or live:try_get("open", false) then
        labels = NEGRules.TierText(track, live:try_get("appealMotivation", false))
    end

    return { labels = labels, landed = landed }
end

--- Send whichever roll this track needs next. Director only.
--- @param track string
function NEGRun.Roll(track)
    local live = NEGRun.Active()
    if live == nil or live:try_get("status") ~= NEGConstants.statusRunning then
        return
    end
    NEGRun.Flow(track):RollNext()
end

--- Drop the roll out on this track. The step is offered again.
--- @param track string
function NEGRun.CancelRoll(track)
    NEGRun.Flow(track):Abandon()
end

--- Drop any roll out on either track, as ending or clearing the negotiation does.
function NEGRun.AbandonRolls()
    NEGRun.Flow(NEGConstants.trackArgument):Abandon()
    NEGRun.Flow(NEGConstants.trackLearn):Abandon()
end

--- Read back any roll that has come in. Director only; safe on any refresh.
function NEGRun.Pump()
    local live = NEGRun.Active()
    if not dmhub.isDM or live == nil or live:try_get("status") ~= NEGConstants.statusRunning then
        return
    end
    NEGRun.Flow(NEGConstants.trackArgument):Pump()
    NEGRun.Flow(NEGConstants.trackLearn):Pump()
end

--- The Director takes the Lead's roll: the scales move, the history records
--- it, and the track can no longer roll or re-roll. Once only, however often
--- it is pressed.
--- @param track string
function NEGRun.AcceptTrack(track)
    local live = NEGRun.Active()
    if not dmhub.isDM or live == nil then
        return
    end

    local flow = NEGRun.Flow(track)
    local record = flow:Record()
    local roll = record.rolls[THCRollFlow.slotLead]
    if roll == nil or record.pending ~= nil or record.accepted == true then
        return
    end

    local outcome = NEGRun.Outcome(live, track)
    local seats = flow:Effective()
    local lead = seats.lead ~= nil and seats.lead.charid or nil
    local assist = seats.assist ~= nil and seats.assist.charid or nil
    local reading = track == NEGConstants.trackLearn

    NEGRun.Mutate("Accept negotiation roll", function(data)
        local target = data.live
        local rec = target ~= nil and target:try_get(track) or nil
        if rec == nil or rec.accepted == true or rec.pending ~= nil then
            return
        end

        rec.accepted = true
        rec.outcome = {
            text = outcome.text,
            interest = outcome.interest,
            patience = outcome.patience,
        }

        --The ladder is unambiguous once the appeal is known. The scales stay
        --clickable for what the rules leave to judgment: a caught lie, a
        --well-roleplayed argument taken as a tier 3.
        if outcome.interest ~= 0 then
            target.interest = NEGConstants.Clamp(target.interest + outcome.interest,
                NEGConstants.scaleMin, target:InterestMax())

            --Interest moved, so the offer moved with it.
            target.offerShared = false
        end

        if outcome.patience ~= 0 then
            target.patience = NEGConstants.Clamp(target.patience + outcome.patience,
                NEGConstants.scaleMin, NEGConstants.scaleMax)
        end

        --The assist folds into the lead's entry rather than becoming its own,
        --so "led 2, assisted 1" counts without counting the argument twice.
        AppendHistory(target, {
            kind = cond(reading, "read", "argument"),
            tier = roll.tier,
            motivation = target.appealMotivation == true,
            lead = cond(reading, nil, lead),
            reader = cond(reading, lead, nil),
            assist = cond(reading, nil, assist),
            interestDelta = outcome.interest,
            patienceDelta = outcome.patience,
        })
    end)

    printf("NEG:: roll accepted track=%s tier=%d interest%+d patience%+d - %s",
        tostring(track), roll.tier or 0, outcome.interest, outcome.patience, outcome.text)
end

--- Move a negotiation that started before the tracks had records onto them.
--- Director only, and once: it runs while the old fields are still there.
--- A roll still out is dropped and offered again; a roll the old code already
--- applied is carried across as taken, so it is never applied twice.
function NEGRun.MigrateLive()
    local live = NEGRun.Active()
    if not dmhub.isDM or live == nil or not HasLegacy(live) then
        return
    end

    local res = live:try_get("resolution")
    if res ~= nil and res.actionId ~= nil then
        THCRoll.Cancel(res.actionId)
    end

    NEGRun.Mutate("Update negotiation", function(data)
        local target = data.live
        if target == nil or not HasLegacy(target) then
            return
        end

        local oldSlots = target:try_get("slots", {})
        local oldRolls = target:try_get("rolls", {})

        --- @param entry table|nil
        --- @return table|nil
        local function Seat(entry)
            if entry == nil or entry.charid == nil then
                return nil
            end
            return {
                charid = entry.charid,
                attrId = entry.attrId,
                skillId = entry.skillId,
                renownEdge = entry.renownEdge,
            }
        end

        --- @param roll table|nil
        --- @return table|nil
        local function Roll(roll)
            if roll == nil then
                return nil
            end
            return {
                total = roll.total,
                naturalRoll = roll.naturalRoll,
                boons = roll.boons,
                banes = roll.banes,
                tier = roll.tier,
            }
        end

        --- @param record table
        --- @param roll table|nil the old lead roll, already applied
        local function Taken(record, roll)
            if roll == nil then
                return
            end
            record.rolls[THCRollFlow.slotLead] = Roll(roll)
            record.accepted = true
            record.outcome = {
                text = roll.outcomeText or "",
                interest = roll.interestDelta or 0,
                patience = roll.patienceDelta or 0,
            }
        end

        local argument = THCRollFlow.NewRecord()
        argument.slots[THCRollFlow.slotLead] = Seat(oldSlots[NEGConstants.slotLead])
        argument.slots[THCRollFlow.slotAssist] = Seat(oldSlots[NEGConstants.slotAssist])
        argument.rolls[THCRollFlow.slotAssist] = Roll(oldRolls[NEGConstants.slotAssist])
        Taken(argument, oldRolls[NEGConstants.slotLead])

        local learn = THCRollFlow.NewRecord()
        learn.slots[THCRollFlow.slotLead] = Seat(oldSlots[NEGConstants.slotLearn])
        Taken(learn, oldRolls[NEGConstants.slotLearn])

        target.argument = argument
        target.learn = learn
        target.slots = {}
        target.rolls = {}
        target.resolution = nil
        target.assistTier = 0
        target.assistPending = nil
    end)

    printf("NEG:: negotiation moved onto roll records")
end

--- Whether this client may move this hero. The Director may move anyone; a
--- player may move only the characters they control.
--- @param charid string
--- @return boolean
function NEGRun.CanManage(charid)
    if dmhub.isDM then
        return true
    end
    local token = dmhub.GetCharacterById(charid)
    return token ~= nil and token.canControl == true
end

--- @param live NEGLive
--- @param charid string
--- @return string
function NEGRun.ParticipantName(live, charid)
    for _, p in ipairs(live:try_get("participants", {})) do
        if p.charid == charid then
            return p:try_get("name", "")
        end
    end
    return ""
end

--- Discard the whole run and go back to the library. Cancels any outstanding
--- request, so nothing survives to block the next negotiation.
function NEGRun.Clear()
    NEGRun.AbandonRolls()

    NEGRun.Mutate("Clear negotiation", function(data)
        data.live = nil
    end)

    GameHud.HidePresentedDialog()
    printf("NEG:: negotiation cleared")
end
