
local ADDON_NAME = "SimpleRestedXPMaxer"

local ADVENTURE_TREE_ID = 1188
local WELL_RESTED_NODE_ID = 110301

local BASE_CAP = 150
local BONUS_PER_RANK = 0.04

local hookedBars = {}
local currentCap = BASE_CAP

--------------------------------------------------
-- TALENT DETECTION
--------------------------------------------------

local function GetWellRestedRank()
    local configID = C_Traits.GetConfigIDByTreeID(1188)
    if not configID then return 0 end

    local node = C_Traits.GetNodeInfo(configID, 110301)
    if not node then return 0 end

    return node.activeRank or node.ranksPurchased or 0
end

local function UpdateCap()
    local rank = GetWellRestedRank()

    currentCap = BASE_CAP * (
        1 + rank * BONUS_PER_RANK
    )
end

--------------------------------------------------
-- XP BAR TEXT
--------------------------------------------------

local function UpdateRestedText(bar)
    if not bar or not bar.OverlayFrame then return end

    local text = bar.OverlayFrame.Text
    if not text then return end

    local maxXP = UnitXPMax("player") or 0
    local restedXP = GetXPExhaustion() or 0

    if maxXP <= 0 then return end

    -- Preserve original vertical positioning (-2 pixels)
    if not bar._restedAnchorSaved then
        local point, relativeTo, relativePoint, x, y =
            text:GetPoint(1)

        if point then
            bar._restedAnchorSaved = true

            text:ClearAllPoints()
            text:SetPoint(
                point,
                relativeTo,
                relativePoint,
                x or 0,
                (y or 0) - 2
            )
        end
    end

    local percentage = (restedXP / maxXP) * 100
    local capXP = maxXP * (currentCap / 100)
    local remaining = math.max(0, capXP - restedXP)

    local suffix

    if restedXP >= capXP then
        suffix = string.format(
            "  |cff00ff00Rested: %.1f%% (CAPPED)|r",
            percentage
        )
    else
        suffix = string.format(
            "  |cff80c0ffRested: %.1f%%|r",
            percentage
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
-- PRIMARY XP BAR
--------------------------------------------------

local function HookExperienceBars()
    local manager = StatusTrackingBarManager

    if not manager or not manager.barContainers then
        print("|cffff0000SimpleRestedXPMaxer: XP manager not found.|r")
        return
    end

    local container = MainStatusTrackingBarContainer

    if not container then
        print("|cffff0000SimpleRestedXPMaxer: Main container not found.|r")
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

    if not bar then
        print("|cffff9900SimpleRestedXPMaxer: Primary XP bar not found.|r")
        return
    end

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

    UpdateRestedText(bar)
end

--------------------------------------------------
-- REFRESH
--------------------------------------------------

local function RefreshExperienceBars()
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

events:SetScript("OnEvent", function(self, event)

    if event == "PLAYER_LOGIN" then
        UpdateCap()
        C_Timer.After(2, HookExperienceBars)

    elseif event == "TRAIT_CONFIG_UPDATED" then
        UpdateCap()
        RefreshExperienceBars()

    else
        RefreshExperienceBars()
    end

end)

print("|cff00ff00SimpleRestedXPMaxer loaded!|r")
