-- Initial Defaults
local defaults = {
    holdTime = 2.0,
    onlyInInstance = false, -- If true, protection only works in Dungeons/Raids
    height = 150
}
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")

-- Constants
local MIN_HOLD_TIME = 0.1
local MAX_HOLD_TIME = 10.0
local BOTTOM_PADDING = 20

local function GetReleaseButton(self)
    return (self.ButtonContainer and self.ButtonContainer.Button1) or 
            (self.Buttons and self.Buttons[1]) or 
            _G[self:GetName().."Button1"] or 
            self.button1
end

-- Function to check if we should apply protection based on location
local function ShouldProtect()
    if not DontReleaseDummyDB.onlyInInstance then return true end
    
    local _, instanceType = GetInstanceInfo()
    -- instanceType returns 'party' for dungeons, 'raid' for raids, or nil in some edge cases
    return (instanceType == "party" or instanceType == "raid")
end

local function PrepareLayout(parent)
    --parent:SetScale(1.26)
    -- 1. Create/Ensure the Text FontStrings exist
    if not parent.ReleaseLockText then
        parent.ReleaseLockText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    end
    if not parent.SpacerTextRow then
        parent.SpacerTextRow = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    
    -- Creating a second FontString for the Addon Title (Row 2)
    if not parent.AddonTitleText then
        parent.AddonTitleText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        parent.AddonTitleText:SetTextColor(0, 1, 0) -- Green title
        parent.AddonTitleText:SetText("Don't Release Dummy!")
    end

    if not parent.LayoutAdjusted then
        -- Row 1: The Default Blizzard Text (Usually parent.text or parent.Text)
        local defaultText = parent.Text or parent.text or parent.SubText
        if defaultText then
            defaultText:ClearAllPoints()
            defaultText:SetPoint("TOP", parent, "TOP", 0, -10)
        end

        -- Row 2: "Don't Release Dummy!"
        parent.AddonTitleText:ClearAllPoints()
        parent.AddonTitleText:SetPoint("TOP", defaultText or parent, "BOTTOM", 0, -10)

        -- Row 3: The Buttons (ButtonContainer)
        if parent.ButtonContainer then
            parent.ButtonContainer:ClearAllPoints()
            parent.ButtonContainer:SetPoint("TOP", parent.AddonTitleText, "BOTTOM", 0, -10)
            
            -- Row 4: "Hold CTRL to Release"
            parent.ReleaseLockText:ClearAllPoints()
            parent.ReleaseLockText:SetPoint("TOP", parent.ButtonContainer, "BOTTOM", 0, -10)
        end
        -- Row 5: spacer row
        parent.SpacerTextRow:ClearAllPoints()
        parent.SpacerTextRow:SetPoint("TOP", parent.ReleaseLockText, "BOTTOM", 0, -1 * BOTTOM_PADDING)

        local totalHeight = math.abs(parent.SpacerTextRow:GetBottom() - parent:GetTop()) 
        parent.AddonTitleText:Show() 
        parent.ReleaseLockText:Show()
        parent.SpacerTextRow:Show() 
        parent:SetHeight(totalHeight)
        parent.LayoutAdjusted = true
    end
    
    return parent.ReleaseLockText
end

local function UpdateReleaseButton(self, elapsed)
    if self.which == "DEATH" and ShouldProtect() then
        local btn = GetReleaseButton(self)
        if not btn then return end
        
        local instruction = PrepareLayout(self)
        
        -- Initialize per-frame timer if needed
        if not self.ctrlTimer then
            self.ctrlTimer = 0
        end
        
        if IsControlKeyDown() then
            self.ctrlTimer = self.ctrlTimer + elapsed
            if self.ctrlTimer >= DontReleaseDummyDB.holdTime then
                btn:Enable()
                instruction:SetText(FERROZ_COLOR:WrapTextInColorCode("UNLOCKED"))
            else
                btn:Disable()
                local remaining = math.max(0, DontReleaseDummyDB.holdTime - self.ctrlTimer)
                instruction:SetText(string.format("|cffff0000HOLDING: %.1fs|r", remaining))
            end
        else
            self.ctrlTimer = 0
            btn:Disable()
            instruction:SetText(string.format("|cffffcc00HOLD CTRL (%.1fs) TO RELEASE|r", DontReleaseDummyDB.holdTime))
        end
    else
        if self.ReleaseLockText then self.ReleaseLockText:SetText("") end
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
                s.LayoutAdjusted = false
            end)
            frame:HookScript("OnHide", function(s)
                -- Hide  custom elements
                if s.AddonTitleText then s.AddonTitleText:Hide() end
                if s.ReleaseLockText then s.ReleaseLockText:Hide() end
                if s.SpacerTextRow then s.SpacerTextRow:Hide() end
                -- Reset the layout flag
                s.LayoutAdjusted = false
                --  the frame height to a standard Blizzard size
                s:SetHeight(defaults.height)
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
        -- Load saved vars or set defaults
        DontReleaseDummyDB = DontReleaseDummyDB or {}
        for k, v in pairs(defaults) do
            if DontReleaseDummyDB[k] == nil then DontReleaseDummyDB[k] = v end
        end       
        -- Validate existing holdTime value
        if DontReleaseDummyDB.holdTime and (DontReleaseDummyDB.holdTime < MIN_HOLD_TIME or DontReleaseDummyDB.holdTime > MAX_HOLD_TIME) then
            DontReleaseDummyDB.holdTime = defaults.holdTime
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
        print("  /drd time # - Set hold time (e.g. /drd time 3)")
        print("  /drd instance - Toggle between Always or Only in Dungeons/Raids")
    end
end