local BD = require("ui/bidi")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local datetime = require("datetime")
local time = require("ui/time")
local util = require("util")

local Providers = {}
local ICON = {
    wifi_on = "",
    wifi_off = "",
    frontlight = "☼",
    frontlight_warmth = "W:",
    up_time = "⏻",
    awake_time = "☀",
    suspend_time = "⏾",
    memory = "",
}

local function getMode(config)
    if config and config.display_mode == "always" then
        return "always"
    end
    return "active_only"
end

Providers.item_order = {
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
}

local function formatDuration(fts)
    if not fts then
        return nil
    end
    return datetime.secondsToClockDuration("modern", time.to_s(fts), true, false, true)
end

local function getCached(state, key, ttl_fts, producer)
    state.metrics_cache = state.metrics_cache or {}
    local now = time.boottime_or_realtime_coarse()
    local cached = state.metrics_cache[key]
    if cached and now - cached.ts <= ttl_fts then
        return cached.value
    end
    local value = producer()
    state.metrics_cache[key] = {
        ts = now,
        value = value,
    }
    return value
end

function Providers.get(item, context)
    local config = context.config
    local state = context.state
    local ui = context.ui
    local powerd = Device:getPowerDevice()

    if item == "custom_text" then
        if config.custom_text == "" then
            return nil
        end
        return config.custom_text
    end

    if item == "clock" then
        return datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    end

    if item == "wifi" then
        if NetworkMgr:isWifiOn() then
            return ICON.wifi_on
        end
        if getMode(config) == "always" then
            return ICON.wifi_off
        end
        return nil
    end

    if item == "ssh" then
        return getCached(state, "ssh", time.s(1), function()
            if util.pathExists("/tmp/dropbear_koreader.pid") then
                return "SSH"
            end
            if getMode(config) == "always" then
                return "SSH-"
            end
            return nil
        end)
    end

    if item == "frontlight_warmth" then
        if not Device:hasNaturalLight() then
            return nil
        end
        local prefix = ICON.frontlight_warmth
        if powerd:isFrontlightOn() then
            local warmth = powerd:frontlightWarmth()
            if warmth then
                return (prefix .. "%d%%"):format(warmth)
            end
        end
        if getMode(config) == "always" then
            return prefix .. "0%"
        end
        return nil
    end

    if item == "frontlight" then
        if not Device:hasFrontlight() then
            return nil
        end
        local prefix = ICON.frontlight
        if powerd:isFrontlightOn() then
            local intensity = powerd:frontlightIntensity()
            if Device:isCervantes() or Device:isKobo() then
                return (prefix .. "%d%%"):format(intensity)
            end
            return (prefix .. "%d"):format(intensity)
        end
        if getMode(config) == "always" then
            if Device:isCervantes() or Device:isKobo() then
                return prefix .. "0%"
            end
            return prefix .. "0"
        end
        return nil
    end

    if item == "battery" then
        if not Device:hasBattery() then
            return nil
        end
        local batt_lvl = powerd:getCapacity()
        local batt_symbol = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), batt_lvl)
        local text = BD.wrap(batt_symbol) .. BD.wrap(tostring(batt_lvl))
        if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
            local aux_batt_lvl = powerd:getAuxCapacity()
            local aux_batt_symbol = powerd:getBatterySymbol(powerd:isAuxCharged(), powerd:isAuxCharging(), aux_batt_lvl)
            text = text .. " " .. BD.wrap("+") .. BD.wrap(aux_batt_symbol) .. BD.wrap(tostring(aux_batt_lvl))
        end
        return text
    end

    if item == "up_time" then
        if not state.start_monotonic_time then
            return nil
        end
        local uptime = time.boottime_or_realtime_coarse() - state.start_monotonic_time
        return ICON.up_time .. formatDuration(uptime)
    end

    if item == "awake_time" then
        if not state.start_monotonic_time then
            return nil
        end
        if not (Device:canSuspend() or Device:canStandby()) then
            return nil
        end
        local uptime = time.boottime_or_realtime_coarse() - state.start_monotonic_time
        local suspend = Device:canSuspend() and (Device.total_suspend_time or 0) or 0
        local standby = Device:canStandby() and (Device.total_standby_time or 0) or 0
        local awake = uptime - suspend - standby
        if awake < 0 then
            awake = 0
        end
        return ICON.awake_time .. formatDuration(awake)
    end

    if item == "suspend_time" then
        if not Device:canSuspend() then
            return nil
        end
        local suspend = Device.total_suspend_time
        if suspend == nil then
            return nil
        end
        return ICON.suspend_time .. formatDuration(suspend)
    end

    if item == "storage" then
        return getCached(state, "storage", time.s(1), function()
            local path = state.current_path
            if (not path or path == "") and ui and ui.file_chooser then
                path = ui.file_chooser.path
            end
            if not path or path == "" then
                return nil
            end
            local usage = util.diskUsage(path)
            if not usage or not usage.available then
                return nil
            end
            local size_text = util.getFriendlySize(usage.available)
            if not size_text then
                return nil
            end
            return size_text
        end)
    end

    if item == "memory" then
        return getCached(state, "memory", time.s(1), function()
            local statm = io.open("/proc/self/statm", "r")
            if not statm then
                return nil
            end
            local _, rss = statm:read("*number", "*number")
            statm:close()
            if not rss then
                return nil
            end
            return ("%s%d"):format(ICON.memory, math.floor(rss / 256))
        end)
    end

    return nil
end

return Providers
