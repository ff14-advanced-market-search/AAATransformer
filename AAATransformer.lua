local addonName = "AAA Transformer"
local addon = LibStub("AceAddon-3.0"):NewAddon(select(2, ...), addonName, "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local LibDeflate = LibStub("LibDeflate")
local LibSerialize = LibStub("LibSerialize")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName);

local defaults = {
	profile = {
		debug = false, -- for addon debugging
		minimap = {
			hide = false,
		},
		stripempty = true,
		trimwhitespace = false,
		windowscale = 1.0,
		editscale = 1.0,
		shiftenter = false,
		settings = {
			discount = "90",
			priceSource = "DBMarket",
			fallback = "1000"
		},
	}
}

local settings = defaults.profile
local optionsFrame
local minimapIcon = LibStub("LibDBIcon-1.0")
local LDB, LDBo

local private = {
	availablePriceSources = {},
	importContext = {},
	itemStringCache = {},
	debugLeaks = nil,
	freeTempTables = {},
	tempTableState = {},
	operationInfo = {},
	settings = {
		groups = {},
	},
}

local VERSION = 1
local MAGIC_STR = "TSM_EXPORT"
local ITEM_MAX_ID = 999999
local IMPORTANT_MODIFIER_TYPES = {
	[9] = true,
}
local EXTRA_STAT_MODIFIER_TYPES = {
	[29] = true,
	[30] = true,
}

local function chatMsg(msg)
	DEFAULT_CHAT_FRAME:AddMessage(addonName .. ": " .. msg)
end

local function debug(msg)
	if addon.db.profile.debug then
		chatMsg(msg)
	end
end

function addon:GetOptions()
	return {
		type = "group",
		set = function(info, val)
			local s = settings; for i = 2, #info - 1 do s = s[info[i]] end
			s[info[#info]] = val; debug(info[#info] .. " set to: " .. tostring(val))
			addon:Update()
		end,
		get = function(info)
			local s = settings; for i = 2, #info - 1 do s = s[info[i]] end
			return s[info[#info]]
		end,
		args = {
			general = {
				type = "group",
				inline = true,
				name = L["general"],
				args = {
					debug = {
						name = L["debug"],
						desc = L["debug_toggle"],
						type = "toggle",
						guiHidden = true,
					},
					config = {
						name = L["config"],
						desc = L["config_toggle"],
						type = "execute",
						guiHidden = true,
						func = function() addon:Config() end,
					},
					show = {
						name = L["show"],
						desc = L["show_toggle"],
						type = "execute",
						guiHidden = true,
						func = function() addon:ToggleWindow() end,
					},
					minimap = {
						order = 15,
						name = L["minimap"],
						desc = L["minimap_toggle"],
						type = "toggle",
						set = function(info, val)
							settings.minimap.hide = not val
							addon:Update()
						end,
						get = function() return not settings.minimap.hide end,
					},
					aheader = {
						name = APPEARANCE_LABEL,
						type = "header",
						cmdHidden = true,
						order = 300,
					},
					windowscale = {
						order = 310,
						type = 'range',
						name = L["window_scale"],
						desc = L["window_scale_desc"],
						min = 0.1,
						max = 5,
						step = 0.1,
						bigStep = 0.1,
						isPercent = true,
					},
					editscale = {
						order = 320,
						type = 'range',
						name = L["font_scale"],
						desc = L["font_scale_desc"],
						min = 0.1,
						max = 5,
						step = 0.1,
						bigStep = 0.1,
						isPercent = true,
					},
				},
			},
		}
	}
end

function addon:RefreshConfig()
	-- things to do after load or settings are reset
	debug("RefreshConfig")
	settings = addon.db.profile
	private.settings = settings
	charName = UnitName("player")

	for k, v in pairs(defaults.profile) do
		if settings[k] == nil then
			settings[k] = table_clone(v)
		end
	end

	settings.loaded = true

	addon:Update()
end

function addon:Update()
	-- things to do when settings change
	if LDBo then
		minimapIcon:Refresh(addonName)
	end

	if addon.gui then -- scale the window
		local frame = addon.gui.frame
		local old = frame:GetScale()
		local new = settings.windowscale

		if old ~= new then
			local top, left = frame:GetTop(), frame:GetLeft()
			frame:ClearAllPoints()
			frame:SetScale(new)
			left = left * old / new
			top = top * old / new
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end

		local file, oldpt, flags = addon.editfont:GetFont()
		local newpt = addon.editfontnorm * settings.editscale

		if math.abs(oldpt - newpt) > 0.25 then
			addon.editfont:SetFont(file, newpt, flags)
		end
	end
end

function addon:OnInitialize()
	addon.db = LibStub("AceDB-3.0"):New("AAATransformerDB", defaults, true)
	addon:RefreshConfig()

	local options = addon:GetOptions()
	LibStub("AceConfigRegistry-3.0"):ValidateOptionsTable(options, addonName)
	LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options, { "aaatransformer" })

	optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName, nil, "general")
	optionsFrame.default = function()
		for k, v in pairs(defaults.profile) do
			settings[k] = table_clone(v)
		end

		addon:RefreshConfig()

		if SettingsPanel:IsShown() then
			addon:Config(); addon:Config()
		end
	end

	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(addon.db)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "Profiles", addonName, "profiles")

	debug("OnInitialize")

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	self.db.RegisterCallback(self, "OnDatabaseReset", "RefreshConfig")
	addon:RegisterChatCommand('aaat', 'HandleChatCommand')
	addon:RegisterChatCommand('aaatf', 'HandleChatCommand')
	addon:RegisterChatCommand('AAATransformer', 'HandleChatCommand')

	private.PreparePriceSources();
	addon:RefreshConfig()
end

function addon:HandleChatCommand(input)
	local args = { strsplit(' ', input) }

	for _, arg in ipairs(args) do
		if arg == 'help' then
			DEFAULT_CHAT_FRAME:AddMessage(
				L["default_chat_message"]
			)
			return
		end
	end

	addon:ToggleWindow()
end

function addon:Config()
	if optionsFrame then
		if (SettingsPanel:IsShown()) then
			SettingsPanel:Hide();
		else
			InterfaceOptionsFrame_OpenToCategory(optionsFrame)
		end
	end
end

function addon:OnEnable()
	debug("OnEnable")

	if LDB then
		return
	end

	if AceLibrary and AceLibrary:HasInstance("LibDataBroker-1.1") then
		LDB = AceLibrary("LibDataBroker-1.1")
	elseif LibStub then
		LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
	end

	if LDB then
		LDBo = LDB:NewDataObject(addonName, {
			type = "launcher",
			label = addonName,
			icon = "Interface\\Icons\\inv_scroll_11",
			OnClick = function(self, button)
				if button == "RightButton" then
					addon:Config()
				else
					addon:ToggleWindow()
				end
			end,
			OnTooltipShow = function(tooltip)
				if tooltip and tooltip.AddLine then
					tooltip:SetText(addonName)
					tooltip:AddLine("|cffff8040" .. L["left_click"] .. "|r " .. L["toogle"])
					tooltip:AddLine("|cffff8040" .. L["right_click"] .. "|r " .. L["options"])
					tooltip:Show()
				end
			end,
		})
	end

	if LDBo then
		minimapIcon:Register(addonName, LDBo, settings.minimap)
	end

	addon:Print(format(L["welcome_message"], addonName))
	addon:Update()
end

function addon:ToggleWindow(keystate)
	if keystate == "down" then return end -- ensure keybind doesnt end up in the text box
	debug("ToggleWindow")

	if not addon.gui then
		addon:CreateWindow()
	end

	if addon.gui:IsShown() then
		addon.gui:Hide()
	else
		addon.gui:Show()
		addon.edit:SetFocus()
		addon:Update()
	end
end

function addon:CreateWindow()
	if addon.gui then
		return
	end

	-- Create main window.
	local frame = AceGUI:Create("Frame")
	frame.frame:SetFrameStrata("MEDIUM")
	frame.frame:Raise()
	frame.content:SetFrameStrata("MEDIUM")
	frame.content:Raise()
	frame:Hide()
	addon.gui = frame
	frame:SetTitle(addonName)
	frame:SetCallback("OnClose", OnClose)
	frame:SetLayout("Fill")
	frame.frame:SetClampedToScreen(true)
	settings.pos = settings.pos or {}
	frame:SetStatusTable(settings.pos)
	addon.minwidth = 800
	addon.minheight = 490
	frame:SetWidth(addon.minwidth)
	frame:SetHeight(addon.minheight)
	frame:SetAutoAdjustHeight(true)
	private.SetEscapeHandler(frame, function() addon:ToggleWindow() end)

	-- Create main group, where everything is placed.
	local mainGroup = AceGUI:Create("SimpleGroup")
	mainGroup:SetLayout("List")
	mainGroup:SetFullWidth(true)
	mainGroup:SetFullHeight(true)
	frame:AddChild(mainGroup)

	-- Create text box, where the text is placed.
	local editBox = AceGUI:Create("MultiLineEditBox")
	mainGroup:AddChild(editBox)
	editBox:SetMaxLetters(0)
	local shortcut = "Control-V"
	if IsMacClient() then
		shortcut = "Command-V"
	end
	editBox:SetLabel(string.format(L["edit_box_label"], shortcut))
	editBox:SetNumLines(10)
	editBox:SetHeight(170)
	editBox:DisableButton(true)
	editBox:SetFullWidth(true)
	editBox:SetText("")
	addon.edit = editBox
	addon.editfont = CreateFont("TransformEditFont")
	addon.editfont:CopyFontObject(ChatFontNormal)
	editBox.editBox:SetFontObject(addon.editfont)
	addon.editfontnorm = select(2, addon.editfont:GetFont())

	-- AceGUI fails at enforcing minimum Frame resize for a container, so fix it
	hooksecurefunc(frame, "OnHeightSet", function(widget, height)
		if (widget ~= addon.gui) then return end
		if (height < addon.minheight) then
			frame:SetHeight(addon.minheight)
		else
			editBox:SetHeight((height - addon.minheight) / 2 + 170)
		end
	end)

	hooksecurefunc(frame, "OnWidthSet", function(widget, width)
		if (widget ~= addon.gui) then return end
		if (width < addon.minwidth) then
			frame:SetWidth(addon.minwidth)
		end
	end)

	local originalHandler = editBox.editBox:GetScript("OnEnterPressed")
	editBox.editBox:SetScript("OnEnterPressed", function(self)
		if originalHandler then
			originalHandler(self)
		else
			editBox.editBox:Insert("\n")
		end
	end)

	-- Create text box, where the JSON is placed.
	local jsonToGroup = AceGUI:Create("SimpleGroup")
	jsonToGroup:SetLayout("Flow")
	jsonToGroup:SetFullWidth(true)
	mainGroup:AddChild(jsonToGroup)

	local jsonItemsBox = AceGUI:Create("MultiLineEditBox")
	jsonToGroup:AddChild(jsonItemsBox)
	jsonItemsBox:SetMaxLetters(0)
	jsonItemsBox:SetLabel(L["json_items_box_label"])
	jsonItemsBox:SetNumLines(10)
	jsonItemsBox:SetHeight(170)
	jsonItemsBox:DisableButton(true)
	jsonItemsBox:SetFullWidth(false)
	jsonItemsBox:SetRelativeWidth(0.5)
	jsonItemsBox:SetText("")
	addon.json = jsonItemsBox
	addon.editfont = CreateFont("TransformEditFont")
	addon.editfont:CopyFontObject(ChatFontNormal)
	jsonItemsBox.editBox:SetFontObject(addon.editfont)
	addon.editfontnorm = select(2, addon.editfont:GetFont())

	-- AceGUI fails at enforcing minimum Frame resize for a container, so fix it
	hooksecurefunc(frame, "OnHeightSet", function(widget, height)
		if (widget ~= addon.gui) then return end
		if (height < addon.minheight) then
			frame:SetHeight(addon.minheight)
		else
			jsonItemsBox:SetHeight((height - addon.minheight) / 2 + 170)
		end
	end)

	hooksecurefunc(frame, "OnWidthSet", function(widget, width)
		if (widget ~= addon.gui) then return end
		if (width < addon.minwidth) then
			frame:SetWidth(addon.minwidth)
		end
	end)

	local originalHandler = jsonItemsBox.editBox:GetScript("OnEnterPressed")
	jsonItemsBox.editBox:SetScript("OnEnterPressed", function(self)
		if originalHandler then
			originalHandler(self)
		else
			jsonItemsBox.editBox:Insert("\n")
		end
	end)

	local jsonPetsBox = AceGUI:Create("MultiLineEditBox")
	jsonToGroup:AddChild(jsonPetsBox)
	jsonPetsBox:SetMaxLetters(0)
	jsonPetsBox:SetLabel(L["json_pets_box_label"])
	jsonPetsBox:SetNumLines(10)
	jsonPetsBox:SetHeight(170)
	jsonPetsBox:DisableButton(true)
	jsonPetsBox:SetFullWidth(false)
	jsonPetsBox:SetRelativeWidth(0.5)
	jsonPetsBox:SetText("")
	addon.jsonItems = jsonPetsBox
	addon.editfont = CreateFont("TransformEditFont")
	addon.editfont:CopyFontObject(ChatFontNormal)
	jsonPetsBox.editBox:SetFontObject(addon.editfont)
	addon.editfontnorm = select(2, addon.editfont:GetFont())

	-- AceGUI fails at enforcing minimum Frame resize for a container, so fix it
	hooksecurefunc(frame, "OnHeightSet", function(widget, height)
		if (widget ~= addon.gui) then return end
		if (height < addon.minheight) then
			frame:SetHeight(addon.minheight)
		else
			jsonPetsBox:SetHeight((height - addon.minheight) / 2 + 170)
		end
	end)

	hooksecurefunc(frame, "OnWidthSet", function(widget, width)
		if (widget ~= addon.gui) then return end
		if (width < addon.minwidth) then
			frame:SetWidth(addon.minwidth)
		end
	end)

	local originalHandler = jsonPetsBox.editBox:GetScript("OnEnterPressed")
	jsonPetsBox.editBox:SetScript("OnEnterPressed", function(self)
		if originalHandler then
			originalHandler(self)
		else
			jsonPetsBox.editBox:Insert("\n")
		end
	end)

	-- Create a group for the dropdowns (target)
	local pasteToGroup = AceGUI:Create("SimpleGroup")
	pasteToGroup:SetLayout("Flow")
	pasteToGroup:SetFullWidth(true)
	mainGroup:AddChild(pasteToGroup)

	local targetDiscount = AceGUI:Create("EditBox")
	settings.settings.discount = settings.settings.discount or "90"
	targetDiscount:SetLabel(L["discount_label"])
	targetDiscount:SetText(settings.settings.discount)
	targetDiscount:SetMaxLetters(3)
	targetDiscount:SetWidth(100)
	targetDiscount:SetCallback("OnEnter", private.UpdateValues)
	targetDiscount:SetCallback("OnTextChanged", function(widget, text)
		settings.settings.discount = targetDiscount:GetText()
		private.UpdateValues()
	end)
	targetDiscount:SetCallback("OnEnterPressed", function(widget)
		targetDiscount:ClearFocus()
	end)
	targetDiscount:DisableButton(true)

	local priceSource = AceGUI:Create("Dropdown")
	addon.priceSource = priceSource
	priceSource:SetMultiselect(false)
	priceSource:SetLabel(L["price_source_label"])
	priceSource:SetWidth(200)
	priceSource:SetCallback("OnEnter", private.UpdateValues)
	priceSource:SetCallback("OnValueChanged", function(widget, event, key)
		settings.settings.priceSource = key
		private.UpdateValues()
	end)
	settings.settings.priceSource = settings.settings.priceSource or "DBMarket"
	private.UpdateValues()
	priceSource:SetValue(settings.settings.priceSource)

	local fallback = AceGUI:Create("EditBox")
	settings.settings.fallback = settings.settings.fallback or "1000"
	fallback:SetLabel(L["fallback_price_label"])
	fallback:SetText(settings.settings.fallback)
	fallback:SetMaxLetters(3)
	fallback:SetWidth(100)
	fallback:SetCallback("OnEnter", private.UpdateValues)
	fallback:SetCallback("OnTextChanged", function(widget, text)
		settings.settings.fallback = fallback:GetText()
		private.UpdateValues()
	end)
	fallback:SetCallback("OnEnterPressed", function(widget)
		fallback:ClearFocus()
	end)
	fallback:DisableButton(true)

	pasteToGroup:AddChild(targetDiscount)
	pasteToGroup:AddChild(priceSource)
	pasteToGroup:AddChild(fallback)

	-- Create group for the buttons
	local buttonsGroup = AceGUI:Create("SimpleGroup")
	buttonsGroup:SetLayout("Flow")
	buttonsGroup:SetFullWidth(true)
	mainGroup:AddChild(buttonsGroup)

	local buttonWidth = 150
	local transformButton = AceGUI:Create("Button")
	transformButton:SetText(L["transform_button"])
	transformButton:SetWidth(buttonWidth)
	transformButton:SetCallback("OnClick", function(widget, button)
		if private.TransformText(editBox:GetText()) then
			jsonItemsBox:SetText(private.importContext.items)
			jsonPetsBox:SetText(private.importContext.pets)
		else
			jsonItemsBox:SetText("{}")
			jsonPetsBox:SetText("{}")
		end
	end)
	buttonsGroup:AddChild(transformButton)

	local clearButton = AceGUI:Create("Button")
	clearButton:SetText(L["clear_button"])
	clearButton:SetWidth(buttonWidth)
	clearButton:SetCallback("OnClick", function(widget, button)
		editBox:SetText("")
		jsonItemsBox:SetText("")
		jsonPetsBox:SetText("")
		editBox:SetFocus()
	end)
	buttonsGroup:AddChild(clearButton)
end

-- ============================================================================
-- Private Helper Functions
-- ============================================================================

local ROOT_GROUP_PATH = ""
local GROUP_SEP = "`"

function private.UpdateValues()
	debug("UpdateValues")
	local widgetPrice = addon.priceSource

	if widgetPrice and not widgetPrice.open then
		debug("Setting list")
		widgetPrice:SetList(private.availablePriceSources)

		debug(settings.settings.priceSource)
		if not private.availablePriceSources[settings.settings.priceSource] then
			settings.settings.priceSource = "DBMarket"
			widgetPrice:SetValue(settings.settings.priceSource)
		end
	end
end

function private.TransformText(text)
	debug("Transforming: " .. text)
	addon.gui:SetStatusText(L["status_text"])
	if private.ProcessTSMGroupString(text) then
		return true
	end
	return false
end

----------------------------------------------------------------------------------
-- AceGUI hacks --

-- hack to hook the escape key for closing the window
function private.SetEscapeHandler(widget, fn)
	widget.origOnKeyDown = widget.frame:GetScript("OnKeyDown")
	widget.frame:SetScript("OnKeyDown", function(self, key)
		widget.frame:SetPropagateKeyboardInput(true)
		if key == "ESCAPE" then
			widget.frame:SetPropagateKeyboardInput(false)
			fn()
		elseif widget.origOnKeyDown then
			widget.origOnKeyDown(self, key)
		end
	end)
	widget.frame:EnableKeyboard(true)
	widget.frame:SetPropagateKeyboardInput(true)
end

-- get available price sources from the different modules
function private.GetAvailablePriceSources()
	local priceSources = {}

	-- TSM
	debug('TSM loaded: ' .. tostring(addon.TSM.IsLoaded()))
	if addon.TSM.IsLoaded() then
		local ps = addon.TSM.GetAvailablePriceSources() or {}
		for k, v in pairs(ps) do
			priceSources[k] = v
		end
	end

	-- Oribos Exchange
	debug('OE loaded: ' .. tostring(addon.OE.IsLoaded()))
	if addon.OE.IsLoaded() then
		local ps = addon.OE.GetAvailablePriceSources() or {}
		for k, v in pairs(ps) do
			priceSources[k] = v
		end
	end

	-- Auctionator
	debug('ATR loaded: ' .. tostring(addon.ATR.IsLoaded()))
	if addon.ATR.IsLoaded() then
		local ps = addon.ATR.GetAvailablePriceSources() or {}
		for k, v in pairs(ps) do
			priceSources[k] = v
		end
	end

	-- addon.Debug.TableToString(priceSources);
	return priceSources
end

function private.PreparePriceSources()
	debug("PreparePriceSources()")

	-- price source check --
	local priceSources = private.GetAvailablePriceSources() or {}
	debug(format("loaded %d price sources", private.tablelength(priceSources)));

	-- only 2 or less price sources -> chat msg: missing modules
	if private.tablelength(priceSources) < 1 then
		StaticPopupDialogs["BA_NO_PRICESOURCES"] = {
			text = L["no_price_sources"],
			button1 = OKAY,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true
		}
		StaticPopup_Show("BA_NO_PRICESOURCES");

		addon:Print(L["addon_disabled"]);
		addon:Disable();
		return
	else
		-- current preselected price source
		local priceSource = private.GetFromDb("settings", "priceSource")

		-- normal price source check against prepared list
		if not priceSources[priceSource] then
			StaticPopupDialogs["BA_INVALID_CUSTOM_PRICESOURCE"] = {
				text = L["invalid_price_sources"],
				button1 = OKAY,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true
			}
			StaticPopup_Show("BA_INVALID_CUSTOM_PRICESOURCE")
		end
	end

	-- sort the list of price sources
	table.sort(priceSources, function(k1, k2) return priceSources[k1] < priceSources[k2] end)
	private.availablePriceSources = priceSources
end

function private.GetFromDb(grp, key, ...)
	if not key then
		return addon.db.profile[grp]
	end
	return addon.db.profile[grp][key]
end

-- Valuate with selected pricing source
function private.GetItemValue(itemString, itemLink, priceSource)
	-- from which addon is our selected price source?
	local selectedPriceSource = addon.CONST.PRICE_SOURCE[private.GetFromDb("settings", "priceSource")]
	if private.startsWith(selectedPriceSource, "OE:") then
		return addon.OE.GetItemValue(itemLink:sub(3), priceSource)
	elseif private.startsWith(selectedPriceSource, "ATR:") then
		return addon.ATR.GetItemValue(itemLink, priceSource)
	else
		return addon.TSM.GetItemValue(itemString, priceSource)
	end
end

function private.tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

function private.startsWith(String, Start)
	return string.sub(String, 1, string.len(Start)) == Start
end

-- ============================================================================
-- Credit for the process of TSM group string functionality and all below goes to TSM addon.
-- ============================================================================
function private.ProcessTSMGroupString(str)
	-- decode and decompress (if it's not a new import, the decode should fail)
	str = LibDeflate:DecodeForPrint(str)
	if not str then
		debug("Not a valid new import string")
		return false
	end
	local numExtraBytes = nil
	str, numExtraBytes = LibDeflate:DecompressDeflate(str)
	if not str then
		debug("Failed to decompress new import string")
		return false
	elseif numExtraBytes > 0 then
		debug("Import string had extra bytes")
		return false
	end

	-- deserialize and validate the data
	local success, magicStr, version, groupName, items, groups, groupOperations, operations, customSources = LibSerialize:Deserialize(str)
	if not success then
		debug("Failed to deserialize new import string")
		return false
	elseif magicStr ~= MAGIC_STR then
		debug("Invalid magic string: " .. tostring(magicStr))
		return false
	elseif version ~= VERSION then
		debug("Invalid version: " .. tostring(version))
		return false
	elseif type(items) ~= "table" then
		debug("Invalid items type: " .. tostring(items))
		return false
	end

	local outputItems = ""
	local outputPets = ""
	outputItems = "{"
	outputPets = "{"
	for itemString, groupPath in pairs(items) do
		local itemLink = type(itemString) == "string" and private.GetItemString(itemString) or "i:"
		local price = (private.GetItemValue(itemString, itemLink, private.GetFromDb("settings", "priceSource")) or 0)
		local discountedPrice = price / 100 / 100 * ((100 - private.GetFromDb("settings", "percent")) / 100)
		local finalPrice
		if (discountedPrice == 0) then
			finalPrice = private.GetFromDb("settings", "fallback")
		else
			finalPrice = discountedPrice
		end
		if (private.startsWith(itemLink, "p:")) then
			outputPets = outputPets .. '\n    "' .. itemLink:sub(3) .. '": ' .. (string.format("%.2f", finalPrice)) .. ','
		else
			outputItems = outputItems .. '\n    "' .. itemLink:sub(3) .. '": ' .. (string.format("%.2f", finalPrice)) .. ','
		end
	end
	outputItems = outputItems:sub(1, -2)
	outputItems = outputItems .. "\n}"
	outputPets = outputPets:sub(1, -2)
	outputPets = outputPets .. "\n}"

	debug("Decoded new import string")
	private.importContext.items = outputItems
	private.importContext.pets = outputPets
	return true
end

function private.GetItemString(item)
	if not item then
		return nil
	end
	if not private.itemStringCache[item] then
		private.itemStringCache[item] = private.ToItemString(item)
	end
	return private.itemStringCache[item]
end

function private.ToItemString(item)
	local paramType = type(item)
	if paramType == "string" then
		item = strtrim(item)
		local itemId = strmatch(item, "^item:(%d+)$")
		if itemId then
			item = "i:" .. itemId
		else
			itemId = strmatch(item, "^[ip]:(%d+)$")
		end
		if itemId then
			if tonumber(itemId) > ITEM_MAX_ID then
				return nil
			end
			-- This is already an itemString
			return item
		end
	elseif paramType == "number" or tonumber(item) then
		local itemId = tonumber(item)
		if itemId > ITEM_MAX_ID then
			return nil
		end
		-- assume this is an itemId
		return "i:" .. item
	else
		error("Invalid item parameter type: " .. tostring(item))
	end

	-- test if it's already (likely) an item string or battle pet string
	if strmatch(item, "^i:([0-9%-:i%+]+)$") then
		return private.FixItemString(item)
	elseif strmatch(item, "^p:([i0-9:]+)$") then
		return private.FixPet(item)
	end

	local result = strmatch(item, "^\124cff[0-9a-z]+\124[Hh](.+)\124h%[.+%]\124h\124r$")
	if result then
		-- it was a full item link which we've extracted the itemString from
		item = result
	end

	-- test if it's an old style item string
	result = strjoin(":", strmatch(item, "^(i)tem:([0-9%-]+):[0-9%-]+:[0-9%-]+:[0-9%-]+:[0-9%-]+:[0-9%-]+:([0-9%-]+)$"))
	if result then
		return private.FixItemString(result)
	end

	-- test if it's an old style battle pet string (or if it was a link)
	result = strjoin(":", strmatch(item, "^battle(p)et:(%d+:%d+:%d+)"))
	if result then
		return private.FixPet(result)
	end
	result = strjoin(":", strmatch(item, "^battle(p)et:(%d+)[:]*$"))
	if result then
		return result
	end
	result = strjoin(":", strmatch(item, "^(p):(%d+:%d+:%d+)"))
	if result then
		return private.FixPet(result)
	end

	-- test if it's a long item string
	result = strjoin(":",
		strmatch(item,
			"(i)tem:([0-9%-]+):[0-9%-]*:[0-9%-]*:[0-9%-]*:[0-9%-]*:[0-9%-]*:([0-9%-]*):[0-9%-]*:[0-9%-]*:[0-9%-]*:[0-9%-]*:[0-9%-]*:([0-9%-:]+)"))
	if result and result ~= "" then
		return private.FixItemString(result)
	end

	-- test if it's a shorter item string (without bonuses)
	result = strjoin(":", strmatch(item, "(i)tem:([0-9%-]+):[0-9%-]*:[0-9%-]*:[0-9%-]*:[0-9%-]*:[0-9%-]*:([0-9%-]*)"))
	if result and result ~= "" then
		return result
	end
end

function private.FixItemString(itemString)
	itemString = gsub(itemString, ":0:", "::") -- remove 0s which are in the middle
	itemString = private.RemoveExtra(itemString)
	return private.FilterBonusIdsAndModifiers(itemString, false, strsplit(":", itemString))
end

function private.FixPet(itemString)
	itemString = private.RemoveExtra(itemString)
	return strmatch(itemString, "^(p:%d+:%d+:%d+)$") or strmatch(itemString, "^(p:%d+:i%d+)$") or
	strmatch(itemString, "^(p:%d+)")
end

function private.RemoveExtra(itemString)
	local num = 1
	while num > 0 do
		itemString, num = gsub(itemString, ":0?$", "")
	end
	return itemString
end

function private.FilterBonusIdsAndModifiers(itemString, importantBonusIdsOnly, itemType, itemId, rand, numBonusIds, ...)
	numBonusIds = tonumber(numBonusIds) or 0
	local numParts = select("#", ...)
	if numParts == 0 then
		return itemString
	end

	-- grab the modifiers and filter them
	local numModifiers = numParts - numBonusIds
	local modifiersStr = (numModifiers > 0 and numModifiers > 1 and numModifiers % 2 == 1) and
	strjoin(":", select(numBonusIds + 1, ...)) or ""
	if modifiersStr ~= "" then
		wipe(private.modifiersTemp)
		wipe(private.modifiersValueTemp)
		wipe(private.extraStatModifiersTemp)
		local num, modifierType = nil, nil
		for modifier in gmatch(modifiersStr, "[0-9]+") do
			modifier = tonumber(modifier)
			if not num then
				num = modifier
			elseif not modifierType then
				modifierType = modifier
			else
				if IMPORTANT_MODIFIER_TYPES[modifierType] then
					tinsert(private.modifiersTemp, modifierType)
					assert(not private.modifiersValueTemp[modifierType])
					private.modifiersValueTemp[modifierType] = modifier
				elseif not importantBonusIdsOnly and EXTRA_STAT_MODIFIER_TYPES[modifierType] then
					tinsert(private.modifiersTemp, modifierType)
					tinsert(private.extraStatModifiersTemp, modifier)
				end
				modifierType = nil
			end
		end
		if #private.modifiersTemp > 0 then
			sort(private.modifiersTemp)
			sort(private.extraStatModifiersTemp)
			-- insert the values into modifiersTemp
			for i = #private.modifiersTemp, 1, -1 do
				local tempModifierType = private.modifiersTemp[i]
				local modifier = nil
				if EXTRA_STAT_MODIFIER_TYPES[tempModifierType] then
					assert(not importantBonusIdsOnly)
					modifier = tremove(private.extraStatModifiersTemp)
				else
					modifier = private.modifiersValueTemp[tempModifierType]
				end
				assert(modifier)
				tinsert(private.modifiersTemp, i + 1, modifier)
			end
			tinsert(private.modifiersTemp, 1, #private.modifiersTemp / 2)
			modifiersStr = table.concat(private.modifiersTemp, ":")
		else
			modifiersStr = ""
		end
	end

	-- filter the bonusIds
	local bonusIdsStr = ""

	-- rebuild the itemString
	itemString = strjoin(":", itemType, itemId, rand, bonusIdsStr, modifiersStr)
	itemString = gsub(itemString, ":0:", "::") -- remove 0s which are in the middle
	return private.RemoveExtra(itemString)
end
