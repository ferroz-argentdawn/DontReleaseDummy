--constants
local INSTANCE_TYPE = {
    ALWAYS = {displayText = "Always", key="ALWAYS", query=nil},
    DUNGEONS = {displayText = "Only in Dungeons",key="DUNGEONS", query={"party"}},
    RAIDS = {displayText = "Only in Raids", key="RAIDS",query={"raid"}},
    DUNGEONS_AND_RAIDS = {displayText = "Only in Dungeons or Raids",key="DUNGEONS_AND_RAIDS", query={"party","raid"}},
}

INSTANCE_TYPE.ALWAYS.nextVal = INSTANCE_TYPE.DUNGEONS
INSTANCE_TYPE.DUNGEONS.nextVal = INSTANCE_TYPE.RAIDS
INSTANCE_TYPE.RAIDS.nextVal = INSTANCE_TYPE.DUNGEONS_AND_RAIDS
INSTANCE_TYPE.DUNGEONS_AND_RAIDS.nextVal = INSTANCE_TYPE.ALWAYS

local HOLD_KEYS = {"CTRL", "ALT", "SHIFT"}
local DEFAULTS = {
    holdTime = 2.0,
    instanceType = INSTANCE_TYPE.ALWAYS.key, -- If true, protection only works in Dungeons/Raids
    height = 150,
    epithet = "Dummy",
    keyName = HOLD_KEYS[1]
}
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")

local MIN_HOLD_TIME = 0.1
local MAX_HOLD_TIME = 10.0
local BOTTOM_PADDING = 20

--functions
local function GetEpithet()
    return DontReleaseDummyDB.epithet or DEFAULTS.epithet
end

local function GetReleaseButton(self)
    return (self.ButtonContainer and self.ButtonContainer.Button1) or
            (self.Buttons and self.Buttons[1]) or
            _G[self:GetName().."Button1"] or
            self.button1
end

local function IsEligibleZone()
    local setting = INSTANCE_TYPE[DontReleaseDummyDB.instanceType] or INSTANCE_TYPE.ALWAYS
    if not setting.query then return true end -- always
    local _, instanceType = GetInstanceInfo()
    for _, allowedType in ipairs(setting.query) do
        if instanceType == allowedType then
            return true
        end
    end
    return false
end
local function ShouldProtect(parent)
    -- Must be the death popup, must be in an eligible zone, and NOT in an active encounter
    return parent.which == "DEATH"
           and IsEligibleZone()
           and not IsEncounterInProgress()
end

local function PrepareLayout(parent)
    if not ShouldProtect(parent) then
        return
    end
    -- Create/Ensure the Text FontStrings exist
    if not parent.ReleaseLockText then
        parent.ReleaseLockText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    end
    if not parent.SpacerTextRow then
        parent.SpacerTextRow = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    if not parent.AddonTitleText then
        parent.AddonTitleText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        parent.AddonTitleText:SetTextColor(0, 1, 0) -- Green title
        parent.AddonTitleText:SetText("Don't Release "..GetEpithet().."!")
    end

    if not parent.LayoutAdjusted then
        local defaultText = parent.Text or parent.text or parent.SubText
        if defaultText then
            defaultText:ClearAllPoints()
            defaultText:SetPoint("TOP", parent, "TOP", 0, -10)
        end

        parent.AddonTitleText:ClearAllPoints()
        parent.AddonTitleText:SetPoint("TOP", defaultText or parent, "BOTTOM", 0, -10)

        if parent.ButtonContainer then
            parent.ButtonContainer:ClearAllPoints()
            parent.ButtonContainer:SetPoint("TOP", parent.AddonTitleText, "BOTTOM", 0, -10)
            parent.ReleaseLockText:ClearAllPoints()
            parent.ReleaseLockText:SetPoint("TOP", parent.ButtonContainer, "BOTTOM", 0, -10)
        end
        parent.SpacerTextRow:ClearAllPoints()
        parent.SpacerTextRow:SetPoint("TOP", parent.ReleaseLockText, "BOTTOM", 0, -1 * BOTTOM_PADDING)

        parent.AddonTitleText:Show()
        parent.ReleaseLockText:Show()
        parent.SpacerTextRow:Show()
        --local totalHeight = math.abs(parent.SpacerTextRow:GetBottom() - parent:GetTop())
        --parent:SetHeight(totalHeight)
        parent.LayoutAdjusted = true
        if parent.Layout then
            parent:Layout() -- Forces the frame to resize based on its children's anchors
        end
    end
    return parent.ReleaseLockText
end

local function CleanupUI(self)
    if self.ReleaseLockText then self.ReleaseLockText:SetText("") end
    if self.AddonTitleText then self.AddonTitleText:Hide() end
    if self.SpacerTextRow then self.SpacerTextRow:Hide() end
    if self.LayoutAdjusted then
        local btn = GetReleaseButton(self)
        if btn then btn:Enable() end -- Run ONCE to hand control back
        self.LayoutAdjusted = false   -- Now the addon stops touching the button
        self:SetHeight(DEFAULTS.height)
    end
end

local function IsHoldKeyDown()
    local key = DontReleaseDummyDB.keyName
    if key == "SHIFT" then return IsShiftKeyDown() end
    if key == "ALT" then return IsAltKeyDown() end
    if key == "CTRL" then return IsControlKeyDown() end
    return IsControlKeyDown() -- default to ctrl
end

local function UpdateReleaseButton(self, elapsed)
    if not ShouldProtect(self) then
        CleanupUI(self)
        return
    end

    local btn = GetReleaseButton(self)
    if not btn then return end

    --fallback, set up if it hasn't been
    if not self.LayoutAdjusted then PrepareLayout(self) end
    if self.AddonTitleText then self.AddonTitleText:Show() end

    -- Initialize per-frame timer if needed
    self.holdTimer = self.holdTimer or 0

    if IsHoldKeyDown() then
        self.holdTimer = self.holdTimer + elapsed
        if self.holdTimer >= DontReleaseDummyDB.holdTime then
            btn:Enable()
            self.ReleaseLockText:SetText(GREEN_FONT_COLOR:WrapTextInColorCode("UNLOCKED"))
            if DontReleaseDummyDB.autoRelease and not self.autoReleasedFired then
                self.autoReleasedFired = true
                RepopMe()
            end
        else
            btn:Disable()
            local remaining = math.max(0, DontReleaseDummyDB.holdTime - self.holdTimer)
            self.ReleaseLockText:SetText(RED_FONT_COLOR:WrapTextInColorCode(string.format("HOLDING: %.1fs", remaining)))
        end
    else
        self.holdTimer = 0
        self.autoReleasedFired = false
        btn:Disable()
        self.ReleaseLockText:SetText(NORMAL_FONT_COLOR:WrapTextInColorCode(string.format("HOLD %s (%.1fs) TO RELEASE", DontReleaseDummyDB.keyName, DontReleaseDummyDB.holdTime)))
    end
end

-- Hook Frames
local function init()
    for i = 1, 4 do
        local frame = _G["StaticPopup"..i]
        if frame then
            frame:HookScript("OnUpdate", UpdateReleaseButton)
            frame:HookScript("OnShow", function(s)
                s.holdTimer = 0
                s.autoReleasedFired = false
                s.LayoutAdjusted = false
                --set up the UI once
                PrepareLayout(s)
            end)
            frame:HookScript("OnHide", function(s)
                s.autoReleasedFired = false
                CleanupUI(s)
            end)
        end
    end
    local version = C_AddOns.GetAddOnMetadata("DontReleaseDummy", "Version") or "1.0.0"
    print(FERROZ_COLOR:WrapTextInColorCode("[DRD] v" .. version) .. " loaded (/drd)")
end

-- Initialize Settings
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "DontReleaseDummy" then
        -- Load saved vars or set DEFAULTS
        DontReleaseDummyDB = DontReleaseDummyDB or {}
        if DontReleaseDummyDB.onlyInInstance ~= nil then
            if DontReleaseDummyDB.onlyInInstance then
                DontReleaseDummyDB.instanceType = INSTANCE_TYPE.DUNGEONS_AND_RAIDS.key
            else
                DontReleaseDummyDB.instanceType = INSTANCE_TYPE.ALWAYS.key
            end
            DontReleaseDummyDB.onlyInInstance = nil
        end

        for k, v in pairs(DEFAULTS) do
            if DontReleaseDummyDB[k] == nil then DontReleaseDummyDB[k] = v end
        end       
        -- Validate existing holdTime value
        if DontReleaseDummyDB.holdTime and (DontReleaseDummyDB.holdTime < MIN_HOLD_TIME or DontReleaseDummyDB.holdTime > MAX_HOLD_TIME) then
            DontReleaseDummyDB.holdTime = DEFAULTS.holdTime
        end
        init()
        -- Unregister event after initialization
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Slash Commands
SLASH_DONTRELEASE1 = "/drd"
SlashCmdList["DONTRELEASE"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "time" and tonumber(arg) then
        local time = tonumber(arg)
        if time >= MIN_HOLD_TIME and time <= MAX_HOLD_TIME then
            DontReleaseDummyDB.holdTime = time
            print(string.format("%s Hold time set to %.1f seconds.", FERROZ_COLOR:WrapTextInColorCode("DRD:"), time))
        else
            print(string.format("|cffff0000DRD:|r Hold time must be between %.1f and %.1f seconds.", MIN_HOLD_TIME, MAX_HOLD_TIME))
        end
    elseif cmd == "epithet" or cmd == "insult" then
        if arg and type(arg) == "string" and arg ~= "" and arg:match("%S") then
            DontReleaseDummyDB.epithet = arg
        else
            DontReleaseDummyDB.epithet = DEFAULTS.epithet
        end
        print(string.format("%s Calling you %s", FERROZ_COLOR:WrapTextInColorCode("DRD:"), DontReleaseDummyDB.epithet))
    elseif cmd == "auto" or cmd == "autorelease" then
        DontReleaseDummyDB.autoRelease = not DontReleaseDummyDB.autoRelease
        local status = DontReleaseDummyDB.autoRelease and "Enabled" or "Disabled"
        print(string.format("%s Autorelease is now %s", FERROZ_COLOR:WrapTextInColorCode("DRD:"), status))
    elseif cmd == "instance" then
        local instanceType = INSTANCE_TYPE[DontReleaseDummyDB.instanceType] or INSTANCE_TYPE.ALWAYS
        instanceType = instanceType.nextVal
        DontReleaseDummyDB.instanceType = instanceType.key
        print(string.format("%s Protection is now active %s", FERROZ_COLOR:WrapTextInColorCode("DRD:"), instanceType.displayText))
    elseif cmd == "key" then
        local selectedKey = nil
        local nextIndex = nil
        local input = arg and arg:upper() or nil
        for i, key in ipairs(HOLD_KEYS) do
            if input == key then selectedKey = key; break; end
            if key == DontReleaseDummyDB.keyName then nextIndex = (i % #HOLD_KEYS) + 1 end
        end
        if selectedKey == nil then
            selectedKey = HOLD_KEYS[nextIndex or 1]
        end
        DontReleaseDummyDB.keyName = selectedKey
        print(string.format("%s Modifier key set to: %s", FERROZ_COLOR:WrapTextInColorCode("DRD:"), DontReleaseDummyDB.keyName))
    elseif cmd == "test" then
        local p = StaticPopup1
        if p:IsShown() and p.which == "DEATH" then
            StaticPopup_Hide("DEATH")
        else
            local dialog = StaticPopup_Show("DEATH")
            if dialog then
                dialog.which = "DEATH"
                -- Force the layout to update immediately
                PrepareLayout(dialog)
                print(FERROZ_COLOR:WrapTextInColorCode("DRD:") .. " Test window toggled ON")

            end
        end
    else
        print(FERROZ_COLOR:WrapTextInColorCode("DontReleaseDummy Commands:"))
        print("  /drd auto - Autorelease after the hold timer.")
        print("  /drd epithet <String> - Change your 'Dummy' nickname.")
        print("  /drd time # - Set hold duration (0.1 to 10 seconds).")
        print("  /drd instance - Cycle mode: Always, Dungeons, Raids, or Both.")
        print("  /drd key <type> - Change modifier to CTRL, ALT, or SHIFT.")
    end
end