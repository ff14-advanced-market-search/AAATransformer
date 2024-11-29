local addonName = "AAA Transformer"
local addon = LibStub("AceAddon-3.0"):NewAddon(select(2, ...), addonName, "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName);

local defaults = {
	profile = {
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
		aaalists = {},
	}
}

local settings = defaults.profile
local optionsFrame
local minimapIcon = LibStub("LibDBIcon-1.0")
local LDB, LDBo

local private = {
	availablePriceSources = {},
	tsmGroups = {},
	availableTsmGroups = {},
	importContext = {},
	itemStringCache = {},
	freeTempTables = {},
	tempTableState = {},
	operationInfo = {},
	settings = {
		groups = {},
	},
	aaalists = {},
}

function addon:GetOptions()
	return {
		type = "group",
		set = function(info, val)
			local s = settings; for i = 2, #info - 1 do s = s[info[i]] end
			s[info[#info]] = val
			addon.Debug.Log(info[#info] .. " set to: " .. tostring(val))
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
	addon.Debug.Log("RefreshConfig")
	settings = addon.db.profile
	private.settings = settings
	private.aaalists = settings.aaalists
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

	addon.Debug.Log("OnInitialize")

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	self.db.RegisterCallback(self, "OnDatabaseReset", "RefreshConfig")
	addon:RegisterChatCommand('aaat', 'HandleChatCommand')
	addon:RegisterChatCommand('aaatf', 'HandleChatCommand')
	addon:RegisterChatCommand('AAATransformer', 'HandleChatCommand')

	private.PreparePriceSources();
	private.PrepareTsmGroups();
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
	addon.Debug.Log("OnEnable")

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
	addon.Debug.Log("ToggleWindow")

	if not addon.gui then
		addon:CreateWindow()
	end

	if addon.gui:IsShown() then
		addon.gui:Hide()
	else
		addon.gui:Show()
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
	local mainGroup = private.CreateGroup("List", frame)
	local editBox = AceGUI:Create("MultiLineEditBox")

	-- Create dropdown group, where everything is placed.
	local dropdownGroup = private.CreateGroup("Flow", mainGroup)

	if (addon.TSM.IsLoaded()) then
		local tsmGroup = private.CreateGroup("List", dropdownGroup)

		-- Create tsm dropdown
		local tsmDropdown = AceGUI:Create("Dropdown")
		tsmGroup:AddChild(tsmDropdown)
		addon.tsmDropdown = tsmDropdown
		tsmDropdown:SetMultiselect(false)
		tsmDropdown:SetLabel(L["tsm_groups_label"])
		tsmDropdown:SetRelativeWidth(0.5)
		tsmDropdown:SetCallback("OnEnter", private.UpdateValues)
		tsmDropdown:SetCallback("OnValueChanged", function(widget, event, key)
			settings.settings.tsmDropdown = key
			editBox:SetText("")
			private.UpdateValues()
		end)
		private.UpdateValues()
		tsmDropdown:SetValue(settings.settings.tsmDropdown)

		-- Create tsm sub group checkbox
		local tsmSubgroups = AceGUI:Create("CheckBox")
		addon.tsmSubgroups = tsmSubgroups
		tsmGroup:AddChild(tsmSubgroups)
		tsmSubgroups:SetType("checkbox")
		tsmSubgroups:SetLabel(L["tsm_checkbox_label"])
		tsmSubgroups:SetValue(true)
	end

	-- Create text box, where the text is placed.
	mainGroup:AddChild(editBox)
	editBox:SetMaxLetters(0)
	local shortcut = "Control-V"
	if IsMacClient() then
		shortcut = "Command-V"
	end
	editBox:SetLabel(string.format(L["edit_box_label"], shortcut))
	editBox:SetNumLines(5)
	editBox:SetHeight(120)
	editBox:DisableButton(true)
	editBox:SetFullWidth(true)
	editBox:SetText(L["example_input"])
	editBox:SetCallback("OnTextChanged", private.ClearDropdown)
	editBox:SetCallback('OnEditFocusGained', function(self)
		if (editBox:GetText() == L["example_input"]) then
			editBox:SetText('')
		end
	end)
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
			editBox:SetHeight((height - addon.minheight) / 2 + 120)
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
	local jsonToGroup = private.CreateGroup("Flow", mainGroup)

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
	local pasteToGroup = private.CreateGroup("Flow", mainGroup)

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
	fallback:SetMaxLetters(7)
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
	local buttonsGroup = private.CreateGroup("Flow", mainGroup)

	local buttonWidth = 150
	local transformButton = AceGUI:Create("Button")
	transformButton:SetText(L["transform_button"])
	transformButton:SetWidth(buttonWidth)
	transformButton:SetCallback("OnClick", function(widget, button)
		if private.TransformText() then
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
		jsonItemsBox:SetText("")
		jsonPetsBox:SetText("")
		if (addon.TSM.IsLoaded()) then
			addon.tsmDropdown:SetValue("")
		end
		editBox:SetText(L["example_input"])
		addon.gui:SetStatusText("")
	end)
	buttonsGroup:AddChild(clearButton)
end

-- ============================================================================
-- Private Helper Functions
-- ============================================================================

function private.CreateGroup(layout, parent)
	local group = AceGUI:Create("SimpleGroup")
	group:SetLayout(layout)
	group:SetFullWidth(true)
	group:SetFullHeight(true)
	parent:AddChild(group)
	return group
end

function private.ClearDropdown()
	addon.tsmDropdown:SetValue("")
	settings.settings.tsmDropdown = ""
end

function private.UpdateValues()
	addon.Debug.Log("UpdateValues")
	local widgetPrice = addon.priceSource

	if widgetPrice and not widgetPrice.open then
		addon.Debug.Log("Setting price source list")
		widgetPrice:SetList(private.availablePriceSources)

		addon.Debug.Log(settings.settings.priceSource)
		if not private.availablePriceSources[settings.settings.priceSource] then
			settings.settings.priceSource = "DBMarket"
			widgetPrice:SetValue(settings.settings.priceSource)
		end
	end

	local widgetTsmDropdown = addon.tsmDropdown
	if widgetTsmDropdown and not widgetTsmDropdown.open then
		addon.Debug.Log("Setting tsm groups dropdown")
		widgetTsmDropdown:SetList(private.availableTsmGroups)
	end
end

function private.TransformText()
	if (addon.tsmDropdown:GetValue() == nil or addon.tsmDropdown:GetValue() == "") then
		if private.ProcessString(addon.edit:GetText()) then
			addon.gui:SetStatusText(L["status_text"])
			return true
		end
	else
		local selectedGroup = private.tsmGroups[private.GetFromDb("settings", "tsmDropdown")]
		local subgroups = addon.tsmSubgroups:GetValue()

		addon.Debug.Log("Transforming: " .. selectedGroup .. " including subgroups: " .. tostring(subgroups))
		if private.ProcessTSMGroup(selectedGroup, subgroups) then
			addon.gui:SetStatusText(L["status_text"])
			return true
		end
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
	if addon.TSM.IsLoaded() then
		local ps = addon.TSM.GetAvailablePriceSources() or {}
		for k, v in pairs(ps) do
			priceSources[k] = v
		end
	end

	-- Oribos Exchange
	if addon.OE.IsLoaded() then
		local ps = addon.OE.GetAvailablePriceSources() or {}
		for k, v in pairs(ps) do
			priceSources[k] = v
		end
	end

	-- Auctionator
	if addon.ATR.IsLoaded() then
		local ps = addon.ATR.GetAvailablePriceSources() or {}
		for k, v in pairs(ps) do
			priceSources[k] = v
		end
	end

	addon.Debug.TableToString(priceSources);
	return priceSources
end

function private.PreparePriceSources()
	addon.Debug.Log("PreparePriceSources()")

	-- price source check --
	local priceSources = private.GetAvailablePriceSources() or {}
	addon.Debug.Log(format("loaded %d price sources", private.tablelength(priceSources)));

	-- only 2 or less price sources -> chat msg: missing modules
	if private.tablelength(priceSources) < 1 then
		StaticPopupDialogs["AT_NO_PRICESOURCES"] = {
			text = L["no_price_sources"],
			button1 = OKAY,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true
		}
		StaticPopup_Show("AT_NO_PRICESOURCES");

		addon:Print(L["addon_disabled"]);
		addon:Disable();
		return
	else
		-- current preselected price source
		local priceSource = private.GetFromDb("settings", "priceSource")

		-- normal price source check against prepared list
		if not priceSources[priceSource] then
			StaticPopupDialogs["TA_INVALID_CUSTOM_PRICESOURCE"] = {
				text = L["invalid_price_sources"],
				button1 = OKAY,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true
			}
			StaticPopup_Show("TA_INVALID_CUSTOM_PRICESOURCE")
		end
	end

	-- sort the list of price sources
	table.sort(priceSources, function(k1, k2) return priceSources[k1] < priceSources[k2] end)
	private.availablePriceSources = priceSources
end

function private.PrepareTsmGroups()
	addon.Debug.Log("PrepareTsmGroups()")

	-- price source check --
	local tsmGroups = addon.TSM.GetGroups() or {}
	addon.Debug.Log(format("loaded %d tsm groups", private.tablelength(tsmGroups)));
	addon.Debug.Log("Groups: " .. private.tableToString(tsmGroups))

	-- only 2 or less price sources -> chat msg: missing modules
	if private.tablelength(tsmGroups) < 1 then
		StaticPopupDialogs["AT_NO_TSMGROUPS"] = {
			text = L["no_tsm_groups"],
			button1 = OKAY,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true
		}
		StaticPopup_Show("AT_NO_TSMGROUPS");

		addon:Print(L["addon_disabled"]);
		addon:Disable();
		return
	end

	private.tsmGroups = tsmGroups

	for k, v in pairs(tsmGroups) do
		local parent, group = addon.TSM.SplitGroupPath(v)
		local _, c = v:gsub("`", "")

		if (parent ~= nil) then
			group = private.lpad(addon.TSM.FormatGroupPath(group), c * 4, " ")
		end
		table.insert(private.availableTsmGroups, k, group)
	end
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
		return addon.OE.GetItemValue(itemString:sub(3), priceSource)
	elseif private.startsWith(selectedPriceSource, "ATR:") then
		return addon.ATR.GetItemValue(itemLink, priceSource)
	else
		return addon.TSM.GetItemValue(itemString, priceSource)
	end
end

function private.lpad(str, len, char)
	return string.rep(char, len) .. str
end

function private.tablelength(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

function private.startsWith(String, Start)
	return string.sub(String, 1, string.len(Start)) == Start
end

function private.tableToString(tbl)
	local result = "{"
	for k, v in pairs(tbl) do
		-- Check the key type (ignore any numerical keys - assume its an array)
		if type(k) == "string" then
			result = result .. "[\"" .. k .. "\"]" .. "="
		end

		-- Check the value type
		if type(v) == "table" then
			result = result .. private.tableToString(v)
		elseif type(v) == "boolean" then
			result = result .. tostring(v)
		else
			result = result .. "\"" .. v .. "\""
		end
		result = result .. ","
	end
	-- Remove leading commas from the result
	if result ~= "{" then
		result = result:sub(1, result:len() - 1)
	end
	return result .. "}"
end

function private.ProcessString(text)
	if (text:find("^i:") == nil and text:find("^p:") == nil) then
		return false
	end
	local tableItems = {}
	for str in string.gmatch(text, "([^,]+)") do
		table.insert(tableItems, str)
	end
	return private.ProcessItems(tableItems)
end

function private.ProcessTSMGroup(group, includeSubgroups)
	local items = {}
	addon.TSM.GetGroupItems(group, includeSubgroups, items)
	return private.ProcessItems(items)
end

function private.ProcessItems(items)
	addon.Debug.Log("Items: " .. private.tableToString(items))

	local outputItems = ""
	local itemCounter = 0
	local outputPets = ""
	local petCounter = 0
	outputItems = "{"
	outputPets = "{"
	for _, itemString in pairs(items) do
		local itemLink = type(itemString) == "string" and addon.TSM.GetItemLink(itemString) or "i:"
		addon.Debug.Log("itemString: " .. itemString)
		addon.Debug.Log("itemLink" .. itemLink)
		if (string.match(itemString, "::")) then
			addon.Debug.Log("skipped item: " .. itemString)
			addon.Debug.Log("skipped item: " .. itemLink)
		else
			local price = (private.GetItemValue(itemString, itemLink, private.GetFromDb("settings", "priceSource")) or 0)
			local discountedPrice = price / 100 / 100 * ((100 - private.GetFromDb("settings", "discount")) / 100)
			local finalPrice
			if (discountedPrice == 0) then
				finalPrice = private.GetFromDb("settings", "fallback")
			else
				finalPrice = discountedPrice
			end

			local parts = {}
			for part in string.gmatch(itemString, "([^:]+)") do
				table.insert(parts, part)
			end
			if (parts[1] == "p") then
				outputPets = outputPets ..
					'\n    "' .. parts[2] .. '": ' .. (string.format("%.2f", finalPrice)) .. ','
				petCounter = petCounter + 1
			else
				outputItems = outputItems ..
					'\n    "' .. parts[2] .. '": ' .. (string.format("%.2f", finalPrice)) .. ','
				itemCounter = itemCounter + 1
			end
		end
	end
	if (itemCounter > 0) then
		outputItems = outputItems:sub(1, -2)
	end
	outputItems = outputItems .. "\n}"
	if (petCounter > 0) then
		outputPets = outputPets:sub(1, -2)
	end
	outputPets = outputPets .. "\n}"

	addon.Debug.Log("Decoded new import string")
	private.importContext.items = outputItems
	private.importContext.pets = outputPets
	settings.aaalists = private.importContext
	return true
end
