local util = require("util")

local Config = {}

Config.SETTING_KEY = "topbar"
Config.SCHEMA_VERSION = 6

Config.SEPARATORS = {
    bar = "|",
    bullet = "•",
    dot = "·",
    en_dash = "-",
    em_dash = "—",
    none = "",
}

Config.defaults = {
    schema_version = Config.SCHEMA_VERSION,
    show = {
        wifi = true,
        ssh = false,
        memory = false,
        storage = false,
        custom_text = false,
        clock = true,
        battery = true,
        frontlight = false,
        frontlight_warmth = false,
        up_time = false,
        awake_time = false,
        suspend_time = false,
    },
    display_mode = "active_only",
    order = {
        "wifi",
        "ssh",
        "memory",
        "storage",
        "custom_text",
        "clock",
        "battery",
        "frontlight",
        "frontlight_warmth",
        "up_time",
        "awake_time",
        "suspend_time",
    },
    custom_text = "KOReader",
    separator = "dot",
    separator_space = 1,
    separator_custom = "*",
    show_path = true,
    auto_refresh_clock = true,
    bold = false,
    touchmenu_use_top_bar_content = true,
}

local valid_modes = {
    always = true,
    active_only = true,
}

local boolean_settings = {
    show_path = true,
    auto_refresh_clock = true,
    bold = true,
    touchmenu_use_top_bar_content = true,
}

local function hasValue(list, needle)
    for _, value in ipairs(list) do
        if value == needle then
            return true
        end
    end
    return false
end

function Config.normalize(config)
    local cfg = type(config) == "table" and config or {}
    local changed = false

    -- Migrate old per-item mode table to global display_mode.
    if cfg.display_mode == nil and type(cfg.mode) == "table" then
        cfg.display_mode = "active_only"
        for _, mode in pairs(cfg.mode) do
            if mode == "always" then
                cfg.display_mode = "always"
                break
            end
        end
        changed = true
    end

    -- Prune unknown top-level keys and fill missing scalar settings.
    for key in pairs(cfg) do
        if Config.defaults[key] == nil then
            cfg[key] = nil
            changed = true
        end
    end
    for key, value in pairs(Config.defaults) do
        if type(value) ~= "table" and cfg[key] == nil then
            cfg[key] = value
            changed = true
        end
    end

    if type(cfg.show) ~= "table" then
        cfg.show = util.tableDeepCopy(Config.defaults.show)
        changed = true
    end
    if type(cfg.order) ~= "table" then
        cfg.order = util.tableDeepCopy(Config.defaults.order)
        changed = true
    end

    -- Normalize show table.
    for item in pairs(cfg.show) do
        if Config.defaults.show[item] == nil then
            cfg.show[item] = nil
            changed = true
        end
    end
    for item, default_value in pairs(Config.defaults.show) do
        if cfg.show[item] == nil then
            cfg.show[item] = default_value
            changed = true
        else
            cfg.show[item] = not not cfg.show[item]
        end
    end

    if type(cfg.display_mode) ~= "string" or not valid_modes[cfg.display_mode] then
        cfg.display_mode = Config.defaults.display_mode
        changed = true
    end

    -- Normalize item order and remove duplicates.
    local normalized_order = {}
    local seen = {}
    for _, item in ipairs(cfg.order) do
        if Config.defaults.show[item] ~= nil and not seen[item] then
            table.insert(normalized_order, item)
            seen[item] = true
        else
            changed = true
        end
    end
    for _, item in ipairs(Config.defaults.order) do
        if not seen[item] then
            table.insert(normalized_order, item)
            changed = true
        end
    end
    if #normalized_order ~= #cfg.order then
        changed = true
    else
        for i, item in ipairs(normalized_order) do
            if cfg.order[i] ~= item then
                changed = true
                break
            end
        end
    end
    cfg.order = normalized_order

    if type(cfg.custom_text) ~= "string" then
        cfg.custom_text = Config.defaults.custom_text
        changed = true
    end
    if type(cfg.separator_custom) ~= "string" then
        cfg.separator_custom = Config.defaults.separator_custom
        changed = true
    end
    if type(cfg.separator) ~= "string" then
        cfg.separator = Config.defaults.separator
        changed = true
    end
    if cfg.separator ~= "custom" and Config.SEPARATORS[cfg.separator] == nil then
        cfg.separator = Config.defaults.separator
        changed = true
    end

    local separator_space = tonumber(cfg.separator_space)
    if not separator_space then
        separator_space = Config.defaults.separator_space
        changed = true
    end
    separator_space = math.floor(separator_space)
    if separator_space < 0 then
        separator_space = 0
        changed = true
    elseif separator_space > 5 then
        separator_space = 5
        changed = true
    end
    cfg.separator_space = separator_space

    for key in pairs(boolean_settings) do
        cfg[key] = not not cfg[key]
    end

    cfg.schema_version = Config.SCHEMA_VERSION
    return cfg, changed
end

function Config.load()
    local defaults = util.tableDeepCopy(Config.defaults)
    local config = G_reader_settings:readSetting(Config.SETTING_KEY, defaults)
    local normalized, changed = Config.normalize(config)
    return normalized, changed
end

function Config.export(config)
    local normalized = Config.normalize(util.tableDeepCopy(config))
    return normalized
end

function Config.separatorGlyph(config)
    if config.separator == "custom" then
        return config.separator_custom or ""
    end
    return Config.SEPARATORS[config.separator] or ""
end

function Config.isKnownItem(item)
    return hasValue(Config.defaults.order, item)
end

return Config
