
local ADDON_NAME = "SimpleRestedXPMaxer"

local ADVENTURE_TREE_ID = 1188
local WELL_RESTED_NODE_ID = 110301

local BASE_CAP = 150
local BONUS_PER_RANK = 0.04

-- Rested XP accrues at 5% of the current level's XP every 8 hours while
-- resting (inn or capital city), and at a quarter of that rate elsewhere.
local REST_GAIN_PERCENT = 5
local REST_GAIN_PERIOD = 8 * 60 * 60
local NOT_RESTING_RATE_FACTOR = 0.25

local TEXT_Y_OFFSET = -2

local hookedBars = {}
local tooltipOwners = {}
local warnedMissingUI = false
local currentCap = BASE_CAP
local currentRank = 0

--------------------------------------------------
-- TALENT DETECTION
--------------------------------------------------

local function GetWellRestedRank()
    if not C_Traits or not C_Traits.GetConfigIDByTreeID then return 0 end

    local configID = C_Traits.GetConfigIDByTreeID(ADVENTURE_TREE_ID)
    if not configID then return 0 end

    local node = C_Traits.GetNodeInfo(configID, WELL_RESTED_NODE_ID)
    if not node then return 0 end

    return node.activeRank or node.ranksPurchased or 0
end

local function UpdateCap()
    currentRank = GetWellRestedRank()

    currentCap = BASE_CAP * (
        1 + currentRank * BONUS_PER_RANK
    )
end

--------------------------------------------------
-- RESTED STATE
--------------------------------------------------

-- Returns nil when there is no XP to track (e.g. max level).
local function GetRestedState()
    local maxXP = UnitXPMax("player") or 0
    if maxXP <= 0 then return nil end

    local restedXP = GetXPExhaustion() or 0
    local capXP = maxXP * (currentCap / 100)
    local missingXP = math.max(0, capXP - restedXP)

    -- XP gained per second while resting.
    local restingRate =
        maxXP * (REST_GAIN_PERCENT / 100) / REST_GAIN_PERIOD

    return {
        maxXP = maxXP,
        restedXP = restedXP,
        capXP = capXP,
        missingXP = missingXP,
        percentage = (restedXP / maxXP) * 100,
        capped = restedXP >= capXP,
        resting = IsResting(),
        secondsToCapResting = missingXP / restingRate,
        secondsToCapOutside =
            missingXP / (restingRate * NOT_RESTING_RATE_FACTOR),
    }
end

local function FormatDuration(seconds)
    seconds = math.ceil(seconds)

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", math.max(1, minutes))
    end
end

local function FormatNumber(value)
    value = math.floor(value + 0.5)

    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end

    return tostring(value)
end

--------------------------------------------------
-- XP BAR TEXT
--------------------------------------------------

local function SameAnchor(a, b)
    return a.point == b.point
        and a.relativeTo == b.relativeTo
        and a.relativePoint == b.relativePoint
        and math.abs(a.x - b.x) < 0.01
        and math.abs(a.y - b.y) < 0.01
end

-- Shift the text down so the longer line clears the bar's top border.
-- Remember the anchor we set; if Blizzard re-anchors the text (Edit Mode,
-- layout refresh), treat that as the new original and shift it again.
local function ApplyTextOffset(bar, text)
    local point, relativeTo, relativePoint, x, y = text:GetPoint(1)
    if not point then return end

    local current = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x or 0,
        y = y or 0,
    }

    if bar._restedAnchor and SameAnchor(current, bar._restedAnchor) then
        return
    end

    current.y = current.y + TEXT_Y_OFFSET

    text:ClearAllPoints()
    text:SetPoint(
        current.point,
        current.relativeTo,
        current.relativePoint,
        current.x,
        current.y
    )

    bar._restedAnchor = current
end

local function UpdateRestedText(bar)
    if not bar or not bar.OverlayFrame then return end

    local text = bar.OverlayFrame.Text
    if not text then return end

    local state = GetRestedState()
    if not state then return end

    ApplyTextOffset(bar, text)

    local suffix

    if state.capped then
        suffix = string.format(
            "  |cff00ff00Rested: %.1f%% (CAPPED)|r",
            state.percentage
        )
    else
        suffix = string.format(
            "  |cff80c0ffRested: %.1f%%|r",
            state.percentage
        )
    end

    local currentText = text:GetText() or ""
    local baseText

    if bar._restedLastText
        and currentText == bar._restedLastText then

        baseText = bar._restedBaseText
    else
        baseText = currentText
    end

    local newText = baseText .. suffix

    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetText(newText)

    bar._restedBaseText = baseText
    bar._restedLastText = newText
end

--------------------------------------------------
-- TOOLTIP
--------------------------------------------------

local function AddRestedTooltipLines(owner)
    local state = GetRestedState()
    if not state then return end

    local tooltip = GameTooltip

    -- Skip if our section is already there (the refresh path may run
    -- Blizzard's OnEnter, which can include this hook).
    for i = 1, tooltip:NumLines() do
        local line = _G["GameTooltipTextLeft" .. i]
        if line and line:GetText() == ADDON_NAME then return end
    end

    -- Blizzard's OnEnter normally builds the tooltip first; if it did not,
    -- start our own so the lines still have somewhere to go.
    if not tooltip:IsShown() then
        tooltip:SetOwner(owner, "ANCHOR_TOP")
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(ADDON_NAME, 0.5, 0.75, 1)

    tooltip:AddDoubleLine(
        "Rested XP:",
        string.format(
            "%s (%.1f%%)",
            FormatNumber(state.restedXP),
            state.percentage
        ),
        1, 1, 1, 1, 1, 1
    )

    tooltip:AddDoubleLine(
        "Rested cap:",
        string.format(
            "%s (%.1f%%, Well Rested %d)",
            FormatNumber(state.capXP),
            currentCap,
            currentRank
        ),
        1, 1, 1, 1, 1, 1
    )

    if state.capped then
        tooltip:AddLine(
            "Rested XP is capped. Resting longer gains nothing.",
            0, 1, 0, true
        )
    else
        tooltip:AddDoubleLine(
            "Until cap:",
            string.format(
                "%s XP (%.1f%%)",
                FormatNumber(state.missingXP),
                (state.missingXP / state.maxXP) * 100
            ),
            1, 1, 1, 1, 1, 1
        )

        tooltip:AddDoubleLine(
            "Time to cap resting:",
            FormatDuration(state.secondsToCapResting),
            1, 1, 1, 0.5, 1, 0.5
        )

        tooltip:AddDoubleLine(
            "Time to cap elsewhere:",
            FormatDuration(state.secondsToCapOutside),
            1, 1, 1, 1, 0.82, 0
        )

        if state.resting then
            tooltip:AddLine("You are resting.", 0.5, 1, 0.5)
        else
            tooltip:AddLine(
                "Not resting. Log out at an inn or city for full rate.",
                1, 0.82, 0, true
            )
        end
    end

    tooltip:Show()
end

-- Rebuild the tooltip if it is open on one of our frames, so the numbers
-- and resting status stay current while hovering.
local function RefreshOpenTooltip()
    if not GameTooltip:IsShown() then return end

    local owner = GameTooltip:GetOwner()
    if not owner or not tooltipOwners[owner] then return end

    local onEnter = owner:GetScript("OnEnter")
    if onEnter then
        onEnter(owner)
    end

    AddRestedTooltipLines(owner)
end

--------------------------------------------------
-- PRIMARY XP BAR
--------------------------------------------------

-- Warn once per session: a missing manager or container means the default
-- UI changed (or another addon replaced it), not a transient state.
local function WarnMissingUI(what)
    if warnedMissingUI then return end
    warnedMissingUI = true

    print(string.format(
        "|cffff0000%s: %s not found, XP bar text disabled.|r",
        ADDON_NAME,
        what
    ))
end

local function HookExperienceBars()
    local manager = StatusTrackingBarManager

    if not manager or not manager.barContainers then
        WarnMissingUI("XP bar manager")
        return
    end

    local container = MainStatusTrackingBarContainer

    if not container then
        WarnMissingUI("Main status bar container")
        return
    end

    local experienceEnum =
        StatusTrackingBarInfo.BarsEnum.Experience

    local bar

    for _, candidateContainer in pairs(manager.barContainers) do
        if candidateContainer == container then
            bar = candidateContainer.bars
                and candidateContainer.bars[experienceEnum]
            break
        end
    end

    -- No XP bar is normal (max level, XP disabled, bar not built yet).
    -- Stay quiet; RefreshExperienceBars retries on the next XP event.
    if not bar then return end

    if hookedBars[bar] then return end

    hookedBars[bar] = true

    if bar.UpdateCurrentText then
        hooksecurefunc(
            bar,
            "UpdateCurrentText",
            function(self)
                UpdateRestedText(self)
            end
        )

        bar:UpdateCurrentText()
    end

    bar:HookScript("OnEnter", AddRestedTooltipLines)
    tooltipOwners[bar] = true

    if bar.ExhaustionTick then
        bar.ExhaustionTick:HookScript("OnEnter", AddRestedTooltipLines)
        tooltipOwners[bar.ExhaustionTick] = true
    end

    UpdateRestedText(bar)
end

--------------------------------------------------
-- REFRESH
--------------------------------------------------

local function RefreshExperienceBars()
    if not next(hookedBars) then
        HookExperienceBars()
    end

    for bar in pairs(hookedBars) do
        if bar.UpdateCurrentText then
            bar:UpdateCurrentText()
        else
            UpdateRestedText(bar)
        end
    end
end

--------------------------------------------------
-- EVENTS
--------------------------------------------------

local events = CreateFrame("Frame")

events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("PLAYER_UPDATE_RESTING")

events:SetScript("OnEvent", function(self, event)

    if event == "PLAYER_LOGIN" then
        UpdateCap()
        C_Timer.After(2, HookExperienceBars)

    elseif event == "TRAIT_CONFIG_UPDATED" then
        UpdateCap()
        RefreshExperienceBars()
        RefreshOpenTooltip()

    else
        RefreshExperienceBars()
        RefreshOpenTooltip()
    end

end)
