local InputDialog = require("ui/widget/inputdialog")
local SortWidget = require("ui/widget/sortwidget")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

local Config = require("topbar/config")

local Menu = {}

local ITEM_MENU_MSGIDS = {
    wifi = "Wi-Fi",
    ssh = "SSH",
    memory = "Memory",
    storage = "Storage",
    clock = "Clock",
    battery = "Battery",
    frontlight = "Brightness level",
    frontlight_warmth = "Warmth level",
    up_time = "Up time",
    awake_time = "Time spent awake",
    suspend_time = "Time in suspend",
}

local ITEM_HELP_MSGIDS = {
    ssh = "Shown only when SSH server is running",
    memory = "RAM used, MiB",
    storage = "Available storage in current path",
}

local SEPARATOR_MSGIDS = {
    dot = "Dot",
    bullet = "Bullet",
    en_dash = "En dash",
    em_dash = "Em dash",
    bar = "Vertical bar",
    none = "No separator",
    custom = "Custom separator",
}

local DISPLAY_MODE_MSGIDS = {
    active_only = "Active only",
    always = "Always",
}

local function getItemMenuText(item)
    local msgid = ITEM_MENU_MSGIDS[item]
    if msgid then
        return C_("Title info item", msgid)
    end
    return item
end

local function getItemHelpText(item)
    local msgid = ITEM_HELP_MSGIDS[item]
    if msgid then
        return _(msgid)
    end
end

local function getSeparatorText(separator_key)
    local msgid = SEPARATOR_MSGIDS[separator_key]
    if msgid then
        return _(msgid)
    end
    return separator_key
end

local function getDisplayModeText(mode)
    local msgid = DISPLAY_MODE_MSGIDS[mode]
    if msgid then
        return _(msgid)
    end
    return mode
end

local MENU_ICONS = {
    title_info = "appbar.settings",
    modules = "appbar.filebrowser",
    configuration = "appbar.settings",
    sort_modules = "appbar.navigation",
    separators = "appbar.menu",
}

local ITEM_ICONS = {
    wifi = "wifi",
    ssh = "appbar.tools",
    memory = "texture-box",
    storage = "appbar.filebrowser",
    custom_text = "appbar.textsize",
    clock = "appbar.navigation",
    battery = "notice-info",
    frontlight = "appbar.settings",
    frontlight_warmth = "appbar.settings",
    up_time = "appbar.navigation",
    awake_time = "appbar.navigation",
    suspend_time = "appbar.navigation",
}

local buildModulesMenu
local refreshMenuAndTitle

local function getDisplayMode(plugin)
    if plugin.config.display_mode == "always" then
        return "always"
    end
    return "active_only"
end

local function buildDisplayModeMenu(plugin)
    local modes = {
        "active_only",
        "always",
    }
    local items = {}
    for _, mode in ipairs(modes) do
        table.insert(items, {
            text_func = function()
                return getDisplayModeText(mode)
            end,
            checked_func = function()
                return getDisplayMode(plugin) == mode
            end,
            callback = function(touchmenu_instance)
                plugin.config.display_mode = mode
                refreshMenuAndTitle(plugin, touchmenu_instance)
            end,
            keep_menu_open = true,
        })
    end
    return items
end

refreshMenuAndTitle = function(plugin, touchmenu_instance, rebuild_item_table_func)
    if plugin.syncTouchMenuInfoPosition then
        plugin:syncTouchMenuInfoPosition()
    end
    plugin:markConfigDirty()
    if touchmenu_instance then
        if type(rebuild_item_table_func) == "function" then
            touchmenu_instance.item_table = rebuild_item_table_func(plugin)
        end
        touchmenu_instance:updateItems()
    end
    plugin:updateTitleBar()
    if plugin.applyTouchMenuInfoPositionForUI then
        plugin:applyTouchMenuInfoPositionForUI()
    end
end

local function showInputDialog(title, input, onChanged)
    local text_dialog
    text_dialog = InputDialog:new{
        title = title,
        input = input or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(text_dialog)
                    end,
                },
                {
                    text = _("Set"),
                    is_enter_default = true,
                    callback = function()
                        onChanged(text_dialog:getInputText())
                        UIManager:close(text_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(text_dialog)
    text_dialog:onShowKeyboard()
end

local function showCustomTextDialog(plugin, touchmenu_instance)
    showInputDialog(
        _("Enter custom text"),
        plugin.config.custom_text or "",
        function(text)
            plugin.config.custom_text = text or ""
            refreshMenuAndTitle(plugin, touchmenu_instance)
        end
    )
end

local function showCustomSeparatorDialog(plugin, touchmenu_instance)
    showInputDialog(
        _("Enter custom separator"),
        plugin.config.separator_custom or "",
        function(text)
            plugin.config.separator_custom = text or ""
            if plugin.config.separator ~= "custom" then
                plugin.config.separator = "custom"
            end
            refreshMenuAndTitle(plugin, touchmenu_instance)
        end
    )
end

local function showSeparatorSpaceDialog(plugin, touchmenu_instance)
    local spin_widget = SpinWidget:new{
        title_text = _("Spaces around separator"),
        value = plugin.config.separator_space,
        value_min = 0,
        value_step = 1,
        value_max = 5,
        callback = function(spin)
            plugin.config.separator_space = spin.value
            refreshMenuAndTitle(plugin, touchmenu_instance)
        end,
    }
    UIManager:show(spin_widget)
end

local function separatorPreview(plugin, separator_key)
    local spaces = string.rep(" ", plugin.config.separator_space)
    local glyph
    if separator_key == "custom" then
        glyph = plugin.config.separator_custom or ""
    else
        glyph = Config.SEPARATORS[separator_key] or ""
    end
    return spaces .. glyph .. spaces
end

local function buildSeparatorMenu(plugin)
    local items = {}
    local separator_order = {
        "dot",
        "bullet",
        "en_dash",
        "em_dash",
        "bar",
        "custom",
        "none",
    }

    for _, separator_key in ipairs(separator_order) do
        table.insert(items, {
            text_func = function()
                return T("%1 '%2'", getSeparatorText(separator_key), separatorPreview(plugin, separator_key))
            end,
            icon = MENU_ICONS.separators,
            checked_func = function()
                return plugin.config.separator == separator_key
            end,
            callback = function(touchmenu_instance)
                plugin.config.separator = separator_key
                refreshMenuAndTitle(plugin, touchmenu_instance)
            end,
            hold_callback = separator_key == "custom" and function(touchmenu_instance)
                showCustomSeparatorDialog(plugin, touchmenu_instance)
            end or nil,
            keep_menu_open = true,
        })
    end

    if #items > 0 then
        items[#items].separator = true
    end

    table.insert(items, {
        text_func = function()
            return T(_("Spaces around separator: %1"), plugin.config.separator_space)
        end,
        icon = MENU_ICONS.separators,
        callback = function(touchmenu_instance)
            showSeparatorSpaceDialog(plugin, touchmenu_instance)
        end,
        keep_menu_open = true,
    })

    return items
end

local function buildSettingsMenu(plugin)
    return {
        {
            text_func = function()
                return _("Bold font")
            end,
            icon = "appbar.textsize",
            checked_func = function()
                return plugin.config.bold
            end,
            callback = function(touchmenu_instance)
                plugin.config.bold = not plugin.config.bold
                refreshMenuAndTitle(plugin, touchmenu_instance)
            end,
            keep_menu_open = true,
        },
        {
            text_func = function()
                return T(_("Display mode: %1"), getDisplayModeText(getDisplayMode(plugin)))
            end,
            icon = "appbar.settings",
            sub_item_table_func = function()
                return buildDisplayModeMenu(plugin)
            end,
        },
        {
            text_func = function()
                return _("Show top bar modules in drop-down menu")
            end,
            icon = "appbar.navigation",
            checked_func = function()
                return plugin.config.touchmenu_use_top_bar_content
            end,
            callback = function(touchmenu_instance)
                plugin.config.touchmenu_use_top_bar_content = not plugin.config.touchmenu_use_top_bar_content
                refreshMenuAndTitle(plugin, touchmenu_instance)
            end,
            keep_menu_open = true,
        },
        {
            text_func = function()
                return _("Auto refresh clock")
            end,
            icon = "appbar.navigation",
            checked_func = function()
                return plugin.config.auto_refresh_clock
            end,
            enabled_func = function()
                return plugin.config.show.clock
            end,
            callback = function(touchmenu_instance)
                plugin.config.auto_refresh_clock = not plugin.config.auto_refresh_clock
                refreshMenuAndTitle(plugin, touchmenu_instance)
            end,
            keep_menu_open = true,
        },
        {
            text_func = function()
                return _("Show file browser path")
            end,
            icon = "appbar.filebrowser",
            checked_func = function()
                return plugin.config.show_path
            end,
            callback = function(touchmenu_instance)
                plugin.config.show_path = not plugin.config.show_path
                refreshMenuAndTitle(plugin, touchmenu_instance)
            end,
            keep_menu_open = true,
        },
        {
            text_func = function()
                local separator_name = getSeparatorText(plugin.config.separator or "dot")
                return T(_("Item separator: %1"), separator_name)
            end,
            icon = MENU_ICONS.separators,
            sub_item_table_func = function()
                return buildSeparatorMenu(plugin)
            end,
        },
    }
end

local function itemMenuText(plugin, item, concise)
    if item == "custom_text" then
        if concise then
            return _("Custom text")
        end
        return T(_("Custom text: '%1'"), plugin.config.custom_text)
    end
    local text = getItemMenuText(item)
    if concise then
        return text
    end
    return text
end

local function buildItemToggleEntry(plugin, item)
    local help_text = getItemHelpText(item)
    return {
        icon = ITEM_ICONS[item] or MENU_ICONS.modules,
        text_func = function()
            return itemMenuText(plugin, item, false)
        end,
        help_text = help_text,
        checked_func = function()
            return plugin.config.show[item]
        end,
        callback = function(touchmenu_instance)
            plugin.config.show[item] = not plugin.config.show[item]
            refreshMenuAndTitle(plugin, touchmenu_instance)
        end,
        hold_callback = item == "custom_text" and function(touchmenu_instance)
            showCustomTextDialog(plugin, touchmenu_instance)
        end or nil,
        keep_menu_open = true,
    }
end

local function showArrangeDialog(plugin, touchmenu_instance)
    local item_table = {}
    for _, item in ipairs(plugin.config.order) do
        table.insert(item_table, {
            text = itemMenuText(plugin, item, true),
            orig_item = item,
            dim = not plugin.config.show[item],
        })
    end

    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Arrange module order"),
        item_table = item_table,
        callback = function()
            for i, row in ipairs(item_table) do
                plugin.config.order[i] = row.orig_item
            end
            refreshMenuAndTitle(plugin, touchmenu_instance, buildModulesMenu)
            UIManager:setDirty(nil, "ui")
        end,
    }
    UIManager:show(sort_widget)
end

buildModulesMenu = function(plugin)
    local module_items = {
        {
            text_func = function()
                return _("Sort modules")
            end,
            icon = MENU_ICONS.sort_modules,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                showArrangeDialog(plugin, touchmenu_instance)
            end,
        },
    }

    module_items[#module_items].separator = true

    for _, item in ipairs(plugin.config.order) do
        table.insert(module_items, buildItemToggleEntry(plugin, item))
    end
    return module_items
end

function Menu.buildRootItems(plugin)
    return {
        {
            text_func = function()
                return _("Modules")
            end,
            icon = MENU_ICONS.modules,
            sub_item_table_func = function()
                return buildModulesMenu(plugin)
            end,
        },
        {
            text_func = function()
                return _("Configuration")
            end,
            icon = MENU_ICONS.configuration,
            sub_item_table_func = function()
                return buildSettingsMenu(plugin)
            end,
        },
    }
end

function Menu.addToMainMenu(plugin, menu_items)
    local entry = {
        text_func = function()
            return _("Top Bar Settings")
        end,
        icon = MENU_ICONS.title_info,
        sub_item_table_func = function()
            return Menu.buildRootItems(plugin)
        end,
    }

    local filebrowser_settings = menu_items.filebrowser_settings
    if filebrowser_settings and type(filebrowser_settings.sub_item_table) == "table" then
        local items = filebrowser_settings.sub_item_table
        if #items > 0 then
            items[#items].separator = true
        end
        table.insert(items, entry)
        return
    end

    -- Fallback for environments where filebrowser_settings isn't directly available.
    entry.sorting_hint = "filebrowser_settings"
    menu_items.topbar = entry
end

return Menu
