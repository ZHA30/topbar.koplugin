local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local TextWidget = require("ui/widget/textwidget")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local GetText = require("gettext")

local Config = require("topbar/config")
local Menu = require("topbar/menu")
local Providers = require("topbar/providers")

local PLUGIN_L10N_FILE = "koreader.mo"
local LOADED_FLAG = "__topbar_i18n_loaded"
local PLUGIN_ROOT = (debug.getinfo(1, "S").source or ""):match("@?(.*/)")

local function currentLocale()
    local locale = G_reader_settings and G_reader_settings:readSetting("language") or _.current_lang
    locale = tostring(locale or "")
    locale = locale:match("^([^:]+)") or locale
    locale = locale:gsub("%..*$", "")
    return locale
end

local function loadPluginTranslations()
    if _G[LOADED_FLAG] then
        return
    end

    if not PLUGIN_ROOT then
        return
    end

    local locale = currentLocale()
    if locale == "" or locale == "C" then
        return
    end

    _G[LOADED_FLAG] = true

    local function tryLoad(lang)
        if lang == "" then
            return false
        end
        local mo_path = string.format("%sl10n/%s/%s", PLUGIN_ROOT, lang, PLUGIN_L10N_FILE)
        local ok, loaded = pcall(function()
            return GetText.loadMO(mo_path)
        end)
        return ok and loaded == true
    end

    if tryLoad(locale) then
        return
    end

    local lang_only = locale:match("^([A-Za-z][A-Za-z])[_%-]")
    if lang_only and tryLoad(lang_only) then
        return
    end

    if locale:lower():match("^zh") then
        tryLoad("zh_CN")
    end
end

local Screen = Device.screen

local TopBar = WidgetContainer:extend{
    name = "topbar",
    is_doc_only = false,
}

local function composeTopBarText(config, state, ui)
    if not config then
        return nil
    end
    local title_texts = {}
    for _, item in ipairs(config.order or {}) do
        if config.show and config.show[item] then
            local text = Providers.get(item, {
                config = config,
                state = state,
                ui = ui,
            })
            if text and text ~= "" then
                table.insert(title_texts, text)
            end
        end
    end
    if #title_texts == 0 then
        return nil
    end
    local spaces = string.rep(" ", config.separator_space or 1)
    local separator = spaces .. Config.separatorGlyph(config) .. spaces
    return table.concat(title_texts, separator)
end

local function applyTouchMenuInfoText(touch_menu)
    if not touch_menu or not touch_menu.time_info then
        return false
    end
    if (touch_menu.page_num or 1) > 1 then
        return false
    end
    if not TopBar._touchmenu_use_top_bar_content then
        return false
    end

    local config = TopBar._touchmenu_config
    if not config then
        return false
    end
    local state = TopBar._touchmenu_state
    if not state then
        state = {
            start_monotonic_time = time.boottime_or_realtime_coarse(),
            metrics_cache = {},
        }
        TopBar._touchmenu_state = state
    end
    local ui = TopBar._touchmenu_ui
    local text = composeTopBarText(config, state, ui)
    if not text or text == "" then
        return false
    end
    if touch_menu.time_info.text == text then
        return false
    end

    touch_menu.time_info:setText(text)
    if touch_menu.device_info and touch_menu.device_info.resetLayout then
        touch_menu.device_info:resetLayout()
    end
    if touch_menu.footer and touch_menu.footer.resetLayout then
        touch_menu.footer:resetLayout()
    end
    if touch_menu.item_group and touch_menu.item_group.resetLayout then
        touch_menu.item_group:resetLayout()
    end
    return true
end

function TopBar:init()
    loadPluginTranslations()

    self.config, self.config_dirty = Config.load()
    self.menu_registered = false
    self.state = {
        start_monotonic_time = time.boottime_or_realtime_coarse(),
        current_path = nil,
        metrics_cache = {},
    }

    self._clock_refresh_task = function()
        self:updateTitleBar()
    end
    self._deferred_refresh_task = function()
        self:updateTitleBar()
    end

    self:syncTouchMenuInfoPosition()
    self:_patchTouchMenu()

    if self.config_dirty then
        logger.info("TopBar: config normalized to current schema")
    end
end

function TopBar:syncTouchMenuInfoPosition()
    TopBar._touchmenu_use_top_bar_content = self.config.touchmenu_use_top_bar_content and true or false
    TopBar._touchmenu_config = self.config
    TopBar._touchmenu_state = self.state
    TopBar._touchmenu_ui = self.ui
end

function TopBar:_patchTouchMenu()
    if TopBar._touchmenu_patched then
        return
    end
    local TouchMenu = require("ui/widget/touchmenu")
    local original_update_items = TouchMenu.updateItems
    TouchMenu.updateItems = function(menu, ...)
        local result = original_update_items(menu, ...)
        if applyTouchMenuInfoText(menu) then
            UIManager:setDirty(menu.show_parent or nil, "ui", menu.dimen)
        end
        return result
    end
    TopBar._touchmenu_patched = true
end

function TopBar:applyTouchMenuInfoPositionForUI()
    local menu_module = self.ui and self.ui.menu
    if not menu_module then
        return
    end
    local menu_container = menu_module.menu_container
    local main_menu = menu_container and menu_container[1]
    if not main_menu then
        return
    end
    if applyTouchMenuInfoText(main_menu) then
        UIManager:setDirty(main_menu.show_parent or nil, "ui", main_menu.dimen)
    end
end

function TopBar:markConfigDirty()
    self.config_dirty = true
end

function TopBar:_unscheduleClockRefresh()
    if self._clock_refresh_task then
        UIManager:unschedule(self._clock_refresh_task)
    end
end

function TopBar:_scheduleClockRefresh()
    self:_unscheduleClockRefresh()
    if self.config.show.clock and self.config.auto_refresh_clock then
        local seconds = tonumber(os.date("%S")) or 0
        local delay = math.max(1, 61 - seconds)
        UIManager:scheduleIn(delay, self._clock_refresh_task)
    end
end

function TopBar:_composeTitleText()
    local title_texts = {}
    for _, item in ipairs(self.config.order) do
        if self.config.show[item] then
            local text = Providers.get(item, {
                config = self.config,
                state = self.state,
                ui = self.ui,
            })
            if text and text ~= "" then
                table.insert(title_texts, text)
            end
        end
    end
    local spaces = string.rep(" ", self.config.separator_space)
    local separator = spaces .. Config.separatorGlyph(self.config) .. spaces
    return table.concat(title_texts, separator)
end

function TopBar:_updateTitlePath()
    if not self.ui or not self.ui.updateTitleBarPath then
        return
    end

    local path = self.state.current_path
    if (not path or path == "") and self.ui.file_chooser then
        path = self.ui.file_chooser.path
    end

    if self.config.show_path and path then
        self.ui:updateTitleBarPath(path)
    else
        self.ui:updateTitleBarPath("")
    end
end

function TopBar:_ensureTitleBarDefaults()
    if not self.ui or not self.ui.title_bar then
        return
    end

    local title_bar = self.ui.title_bar
    if self.state.default_subtitle == nil then
        self.state.default_subtitle = title_bar.subtitle
    end
    if self.state.default_title_top_padding == nil then
        self.state.default_title_top_padding = title_bar.title_top_padding
    end
    if self.state.default_bottom_padding == nil then
        self.state.default_bottom_padding = title_bar.bottom_v_padding
    end
    if self.state.default_title_face == nil then
        self.state.default_title_face = title_bar.info_text_face
    end
    if self.state.subtitle_reserve_height == nil then
        local subtitle_height = 0
        if title_bar.subtitle_widget then
            subtitle_height = title_bar.subtitle_widget:getSize().h
        elseif title_bar.subtitle_face then
            local probe = TextWidget:new{
                text = "",
                face = title_bar.subtitle_face,
                padding = 0,
            }
            subtitle_height = probe:getSize().h
            probe:free()
        end
        self.state.subtitle_reserve_height = (title_bar.title_subtitle_v_padding or 0) + subtitle_height
    end
    if self.state.reference_titlebar_heights == nil then
        self.state.reference_titlebar_heights = {}
    end
end

function TopBar:_applySubtitleVisibility()
    if not self.ui or not self.ui.title_bar then
        return
    end

    local title_bar = self.ui.title_bar
    self:_ensureTitleBarDefaults()

    local target_subtitle
    if self.config.show_path then
        target_subtitle = self.state.default_subtitle
        if target_subtitle == nil then
            target_subtitle = ""
        end
    else
        target_subtitle = nil
    end
    local target_title_top_padding = self.state.default_title_top_padding or title_bar.title_top_padding

    if title_bar.subtitle ~= target_subtitle or title_bar.title_top_padding ~= target_title_top_padding then
        title_bar.subtitle = target_subtitle
        title_bar.title_top_padding = target_title_top_padding
        title_bar:clear()
        title_bar:init()
    end
end

function TopBar:_applyFontStyle()
    if not self.ui or not self.ui.title_bar then
        return
    end

    local title_bar = self.ui.title_bar
    self:_ensureTitleBarDefaults()

    local default_title_face = self.state.default_title_face
    local default_bottom_padding = self.state.default_bottom_padding
    local default_title_top_padding = self.state.default_title_top_padding or title_bar.title_top_padding
    local target_title_face
    local base_bottom_padding

    if self.config.bold then
        target_title_face = nil
        base_bottom_padding = default_bottom_padding
    else
        target_title_face = default_title_face
        base_bottom_padding = default_bottom_padding + Screen:scaleBySize(5)
    end

    local style_key = self.config.bold and "bold" or "normal"
    local has_changed = title_bar.title_face ~= target_title_face
        or title_bar.bottom_v_padding ~= base_bottom_padding
        or title_bar.title_top_padding ~= default_title_top_padding
    if has_changed then
        title_bar.title_face = target_title_face
        title_bar.bottom_v_padding = base_bottom_padding
        title_bar.title_top_padding = default_title_top_padding
        title_bar:clear()
        title_bar:init()
    end

    if self.config.show_path then
        self.state.reference_titlebar_heights[style_key] = title_bar:getHeight()
        return
    end

    local reference_height = self.state.reference_titlebar_heights[style_key]
    if reference_height == nil then
        reference_height = title_bar:getHeight() + (self.state.subtitle_reserve_height or 0)
        self.state.reference_titlebar_heights[style_key] = reference_height
    end

    local title_height = title_bar.title_widget and title_bar.title_widget:getSize().h or 0
    if title_height <= 0 then
        return
    end

    local button_center_y
    local function updateButtonCenter(icon_button)
        if not icon_button or not icon_button.image then
            return
        end
        local image_h = icon_button.image:getSize().h
        if not image_h or image_h <= 0 then
            return
        end
        local center_y = (icon_button.padding_top or title_bar.button_padding or 0) + (image_h / 2)
        if button_center_y == nil or center_y > button_center_y then
            button_center_y = center_y
        end
    end
    updateButtonCenter(title_bar.left_button)
    updateButtonCenter(title_bar.right_button)
    if button_center_y == nil then
        button_center_y = reference_height / 2
    end

    local aligned_top_padding = math.max(0, math.floor(button_center_y - (title_height / 2)))
    local aligned_bottom_padding = reference_height - title_height - aligned_top_padding
    if aligned_bottom_padding < 0 then
        aligned_bottom_padding = 0
        aligned_top_padding = math.max(0, reference_height - title_height)
    end

    if title_bar.title_top_padding ~= aligned_top_padding or title_bar.bottom_v_padding ~= aligned_bottom_padding then
        title_bar.title_top_padding = aligned_top_padding
        title_bar.bottom_v_padding = aligned_bottom_padding
        title_bar:clear()
        title_bar:init()
    end
end

function TopBar:updateTitleBar()
    if not self.ui or self.ui.title_bar == nil then
        return
    end

    self:_applySubtitleVisibility()
    self:_applyFontStyle()
    self.ui.title_bar:setTitle(self:_composeTitleText())
    self:_updateTitlePath()
    self:_scheduleClockRefresh()
end

function TopBar:onPathChanged(path)
    if not self.menu_registered and self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
        self.menu_registered = true
    end
    self.state.current_path = path
    if self.state.metrics_cache then
        self.state.metrics_cache.storage = nil
    end
    UIManager:nextTick(self._deferred_refresh_task)
end

function TopBar:onSetRotationMode()
    UIManager:nextTick(self._deferred_refresh_task)
end

TopBar.onNetworkConnected = TopBar.updateTitleBar
TopBar.onNetworkDisconnected = TopBar.updateTitleBar
TopBar.onCharging = TopBar.updateTitleBar
TopBar.onNotCharging = TopBar.updateTitleBar
TopBar.onResume = TopBar.updateTitleBar
TopBar.onTimeFormatChanged = TopBar.updateTitleBar
TopBar.onFrontlightStateChanged = TopBar.updateTitleBar
TopBar.onToggleSSHServer = TopBar.updateTitleBar

function TopBar:onFlushSettings()
    if self.config_dirty then
        G_reader_settings:saveSetting(Config.SETTING_KEY, Config.export(self.config))
        self.config_dirty = false
    end
end

function TopBar:onCloseWidget()
    self:_unscheduleClockRefresh()
    if self._deferred_refresh_task then
        UIManager:unschedule(self._deferred_refresh_task)
    end
end

function TopBar:addToMainMenu(menu_items)
    Menu.addToMainMenu(self, menu_items)
end

return TopBar
