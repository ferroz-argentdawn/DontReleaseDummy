-- Initial DEFAULTS
local DEFAULTS = {
    holdTime = 2.0,
    onlyInInstance = false, -- If true, protection only works in Dungeons/Raids
    height = 150,
    epithet = "Dummy"
}
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")

-- Constants
local MIN_HOLD_TIME = 0.1
local MAX_HOLD_TIME = 10.0
local BOTTOM_PADDING = 20

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
    --if set to apply open world, apply
    if not DontReleaseDummyDB.onlyInInstance then return true end
    --else check isntance type
    local _, instanceType = GetInstanceInfo()
    return (instanceType == "party" or instanceType == "raid")
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
    self.ctrlTimer = self.ctrlTimer or 0

    if IsControlKeyDown() then
        self.ctrlTimer = self.ctrlTimer + elapsed
        if self.ctrlTimer >= DontReleaseDummyDB.holdTime then
            btn:Enable()
            self.ReleaseLockText:SetText(GREEN_FONT_COLOR:WrapTextInColorCode("UNLOCKED"))
            if DontReleaseDummyDB.autoRelease and not self.autoReleasedFired then
                self.autoReleasedFired = true
                RepopMe()
            end
        else
            btn:Disable()
            local remaining = math.max(0, DontReleaseDummyDB.holdTime - self.ctrlTimer)
            self.ReleaseLockText:SetText(RED_FONT_COLOR:WrapTextInColorCode(string.format("HOLDING: %.1fs", remaining)))
        end
    else
        self.ctrlTimer = 0
        self.autoReleasedFired = false
        btn:Disable()
        self.ReleaseLockText:SetText(NORMAL_FONT_COLOR:WrapTextInColorCode(string.format("HOLD CTRL (%.1fs) TO RELEASE", DontReleaseDummyDB.holdTime)))
    end
end

-- Hook Frames
local function init()
    for i = 1, 4 do
        local frame = _G["StaticPopup"..i]
        if frame then
            frame:HookScript("OnUpdate", UpdateReleaseButton)
            frame:HookScript("OnShow", function(s)
                s.ctrlTimer = 0
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
        DontReleaseDummyDB.onlyInInstance = not DontReleaseDummyDB.onlyInInstance
        local status = DontReleaseDummyDB.onlyInInstance and "ONLY in instances" or "ALWAYS"
        print(string.format("%s Protection is now active %s", FERROZ_COLOR:WrapTextInColorCode("DRD:"), status))
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
        print("  /drd auto - Autorelease after holding ctrl")
        print("  /drd epithet <String> - Change the name you get called")
        print("  /drd time # - Set hold time (e.g. /drd time 3)")
        print("  /drd instance - Toggle between Always or Only in Dungeons/Raids")
    end
end