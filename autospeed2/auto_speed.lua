--[[
    Copy auto_speed_config.lua.example to auto_speed_config.lua and change the options in that file.

    https://github.com/kevinlekiller/mpv_scripts
--]]
--[[
    Copyright (C) 2015  kevinlekiller

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
    https://www.gnu.org/licenses/gpl-2.0.html
--]]

local _global = {
    osd_start = mp.get_property_osd("osd-ass-cc/0"),
    osd_end = mp.get_property_osd("osd-ass-cc/1"),
    utils = require 'mp.utils',
    -- I will keep adding these as I find them.
    -- You can also toggle the logFps variable below if you want to help.
    -- Some of these are good, they are there to prevent a call to ffprobe.
    knownFps = {
        [23.975986] = 13978/583,
        [23.976]    = 2997/125,
        [23.976025] = 24000/1001,
        [23.976044] = 27021/1127,
        [29.969999] = 2997/100,
        [29.970030] = 30000/1001,
        [30.000000] = 30/1,
        [59.939999] = 2997/50
    },
    modes = {},
    temp = {},
    logFps = false -- Log unknown fps to ~/mpv_unk_fps.log
}

function fileExists(path)
    local test = io.open(path, "r")
    if (test == nil) then
        return false
    end
  return io.close(test)
end

config = {}
function setConfig()
    if (fileExists(string.match(debug.getinfo(2, "S").source:sub(2), "(.*/)") .. "auto_speed_config.lua")) then
        return require "auto_speed_config"
    end
    config = {
        use_xrandr = false,
        use_ffprobe = false,
        display = "HDMI1",
        resolution  = "1920x1080",
        exit_drr = "",
        thresholds = {
            min_speed = 0.9,
            max_speed = 1.1
        },
        osd_displayed = false,
        osd_start = false,
        osd_time = 10,
        osd_key = "y"
    }
end
setConfig()

function round(number)
    return math.floor(number + 0.5)
end

function notInt(integer)
    return (tonumber(integer) == nil)
end

function osdEcho()
    if (config.osd_displayed == true) then
        mp.osd_message(_global.temp["output"], config.osd_time)
    end
end

function main()
    _global.temp = {}
    _global.temp["fps"] = tonumber(mp.get_property("fps"))
    if (_global.temp["fps"] == nil) then
        return
    end
    
    _global.temp["start_drr"] = tonumber(mp.get_property("display-fps"))
    if (_global.temp["start_drr"] == nil) then
        return
    end
    
    _global.temp["fps"] = getFfprobeFps()
    wanted_drr = findRefreshRate()
    
    _global.temp["drr"] = tonumber(mp.get_property("display-fps"))
    -- If we didn't get the updated display refresh rate, sleep and try again.
    if (wanted_drr ~= _global.temp["start_drr"] and wanted_drr > 0 and _global.temp["drr"] == _global.temp["start_drr"]) then
        os.execute("sleep 1")
        _global.temp["drr"] = tonumber(mp.get_property("display-fps"))
    end
    
    _global.temp["original_speed"] = mp.get_property("speed")
    
    determineSpeed()
    
    if (_global.temp["speed"] > 0 and _global.temp["speed"] > config.thresholds.min_speed and _global.temp["speed"] < config.thresholds.max_speed) then
        mp.set_property("speed", _global.temp["speed"])
    end
    
    if (config.osd_displayed == true) then
        setOSD()
        if (config.osd_start == true) then
            osdEcho()
        end
    end
end

function setOSD()
    _global.temp["output"] = (_global.osd_start ..
        "{\\b1}Original monitor refresh rate{\\b0}\\h\\h" .. _global.temp["start_drr"] .. "Hz\\N" ..
        "{\\b1}Current  monitor refresh rate{\\b0}\\h\\h" .. _global.temp["drr"] .. "Hz\\N" ..
        "{\\b1}Original video fps{\\b0}\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h" .. _global.temp["fps"] .. "fps\\N" ..
        "{\\b1}Current  video fps{\\b0}\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h\\h" .. (_global.temp["fps"] * _global.temp["speed"]) .. "fps\\N" ..
        "{\\b1}Original video playback fps{\\b0}\\h\\h\\h\\h\\h" .. _global.temp["relative_fps"] .. "fps\\N" ..
        "{\\b1}Current  video playback fps{\\b0}\\h\\h\\h\\h\\h" .. (_global.temp["relative_fps"] * _global.temp["speed"]) .. "fps\\N" ..
        "{\\b1}Original mpv speed setting{\\b0}\\h\\h\\h\\h\\h\\h" .. _global.temp["original_speed"] .. "x\\N" ..
        "{\\b1}Current  mpv speed setting{\\b0}\\h\\h\\h\\h\\h\\h" .. _global.temp["speed"] .. "x" ..
        _global.osd_end
    )
end

function getFfprobeFps()
    -- Even if the user doesn't use ffprobe, we can use known values.
    local temp = _global.knownFps[_global.temp["fps"]]
    if (temp ~= nil) then
        return temp
    end
    if (config.use_ffprobe == false) then
        return _global.temp["fps"]
    end
    -- Get video file name.
    local video = mp.get_property("stream-path")
    if (fileExists(video) == false) then
        return _global.temp["fps"]
    end
    local command = {
        ["cancellable"] = "false",
        ["args"] = {
            [1] = "ffprobe",
            [2] = "-select_streams",
            [3] = "v",
            [4] = "-v:" .. mp.get_property("ff-vid"),
            [5] = "quiet",
            [6] = "-show_streams",
            [7] = "-show_entries",
            [8] = "stream=avg_frame_rate,r_frame_rate",
            [9] = "-print_format",
            [10] = "json",
            [11] = video
        }
    }
    local output = _global.utils.subprocess(command)
    if (output == nil) then
        return _global.temp["fps"]
    end
    
    local output = _global.utils.parse_json(output.stdout)
    -- Make sure we got data, and avg_frame_rate is the same as r_frame_rate, otherwise the video is not constant fps.
    if (output == nil or output == error or output.streams[1].avg_frame_rate ~= output.streams[1].r_frame_rate) then
        return _global.temp["fps"]
    end
    
    local first, second = output.streams[1].avg_frame_rate:match("([0-9]+)[^0-9]+([0-9]+)")
    if (notInt(first) or notInt(second)) then
        return _global.temp["fps"]
    end
    if (_global.logFps == true) then
        os.execute("echo [$(date)] " .. mp.get_property("filename") .. " [" .. _global.temp["fps"] .. "] = " .. output.streams[1].avg_frame_rate .. ", >> ~/mpv_unk_fps.log") 
    end
    
    local ff_fps = first / second
    if (ff_fps < 1) then
        return _global.temp["fps"]
    end
    _global.knownFps[_global.temp["fps"]] = ff_fps
    return ff_fps
end

function determineSpeed()
    local speed = 0
    local difference = 1
    local relative_fps = 0
    if (_global.temp["drr"] > _global.temp["fps"]) then
        difference = (_global.temp["drr"] / _global.temp["fps"])
        if (difference >= 2) then
            -- fps = 24fps, drr = 60hz
            -- difference = 60hz/24fps = 3 rounded
            -- 24fps * 3 = 72fps
            -- 60hz / 72fps = 0.833333333333 speed
            -- 72fps * 0.833333333333 = 60fps
            difference = round((_global.temp["drr"] / _global.temp["fps"]))
            speed = (_global.temp["drr"] / (_global.temp["fps"] * difference))
        else
            -- fps = 50fps, drr = 60hz
            -- 60hz / 50fps = 1.2 speed
            -- 50fps * 1.2 speed = 60fps
            
            -- fps = 59.94fps, drr = 60hz
            -- 60hz / 59.94fps  = 1.001001001001001 speed
            -- 59.94fps * 1.001001001001001 = 60fps
            speed = difference
        end
        if ((_global.temp["drr"] - _global.temp["fps"]) < 1) then
            relative_fps = _global.temp["fps"]
        else
            relative_fps = _global.temp["fps"] * difference
        end
    elseif (_global.temp["drr"] < _global.temp["fps"]) then
        difference = (_global.temp["fps"] / _global.temp["drr"])
        if (difference >= 2) then
            -- fps = 120fps, drr = 25hz
            -- difference = 120fps/25hz = 5 rounded
            -- 120fps/5 = 24fps ; 25hz / 24fps = 1.04166666667 speed
            -- 24fps * 1.04166666667 speed = 25fps
            difference = round((_global.temp["fps"] / _global.temp["drr"]))
            speed = (_global.temp["drr"] / (_global.temp["fps"] / difference))
        else
            -- fps = 60fps, drr = 50hz
            -- difference = 50hz / 60fps = 0.833333333333 speed
            -- 60fps * 0.833333333333 speed = 50fps
            
            -- fps = 60fps, drr = 59.94hz
            -- difference = 59.94hz / 60fps = 0.999 speed
            -- 60fps * 0.999 speed = 59.94fps
            speed = (_global.temp["drr"] / _global.temp["fps"])
        end
        if ((_global.temp["fps"] - _global.temp["drr"]) < 1) then
            relative_fps = _global.temp["fps"]
        else
            relative_fps = _global.temp["fps"] / difference
        end
    elseif (_global.temp["drr"] == _global.temp["fps"]) then
        speed = 1
        relative_fps = _global.temp["fps"]
    end
    _global.temp["speed"] = speed
    _global.temp["relative_fps"] = relative_fps
end

function findRefreshRate()
    if (config.use_xrandr == false or getXrandrRates() == false) then
        return 0
    end
    local round_fps = round(_global.temp["fps"])
    -- If video FPS is 24 fps, 240 / 24 = 10, try 10 times to find a suitable monitor mode,
    -- for example: 24, 48, 72, 96, 120, 144, 168, 192, 226, 240 hz
    -- TODO? Maybe add fallback code if for example the video is 120fps and the monitor
    -- can only go as high as 60hz, although this will lead to dropped frames.
    local iterator = (240 / round_fps)
    if (iterator < round_fps) then
        iterator = 1
    end
    for rate, val in pairs(_global.modes) do
        local min = (rate * config.thresholds.min_speed)
        local max = (rate * config.thresholds.max_speed)
        for multiplier = 1, iterator do
            local multiplied_fps = (multiplier * round_fps)
            if (multiplied_fps >= min and multiplied_fps <= max) then
                setXrandrRate(val["mode"])
                return val["clock"]
            end
        end
    end
    return 0
end

function setXrandrRate(mode)
    if (config.use_xrandr == true) then
        local command = {
            ["cancellable"] = "false",
            ["args"] = {
                [1] = "xrandr",
                [2] = "--output",
                [3] = tostring(config.display),
                [4] = "--mode",
                [5] = tostring(mode)
            }
        }
        _global.utils.subprocess(command)
    end
end

function getXrandrRates()
    if (_global.modes == false) then
        return false
    end
    local vars = {
        handle = assert(io.popen("xrandr --verbose")),
        foundDisp = false,
        foundRes = false,
        count = 0,
        temp = {}
    }
    
    for line in vars.handle:lines() do
        if (vars.foundDisp == true) then -- We found the display name.
            if (string.match(line, "^%S") ~= nil) then
                break -- We reached the next display or EOF.
            end
            if (string.match(line, "^%s+" .. config.resolution) ~= nil) then -- Look for screen resolution.
                vars.foundRes = true
            end
            if (vars.foundRes == true) then -- We found a matching screen resolution.
                vars.count = vars.count + 1
                if (vars.count == 1) then -- Log the mode name / pixel clock speed.
                    local mode, pclock = string.match(line, "%((.+)%)%s+([%d.]+)MHz")
                    vars.temp = {["mode"] = mode, ["pclock"] = pclock, ["htotal"] = "", ["vtotal"] = "", ["clock"] = ""}
                elseif (vars.count == 2) then -- Log the total horizontal pixels.
                    vars.temp["htotal"] = string.match(line, "total%s+(%d+)")
                elseif (vars.count == 3) then -- Get the total vertical pixels, calculate refresh rate, log it.
                    local vtotal, clock = string.match(line, "total%s+(%d+).+clock%s+([%d.]+)[KkHh]+z")
                    _global.modes[round(clock)] = {
                        ["clock"] = ((vars.temp["pclock"] * 1000000) / (vtotal * vars.temp["htotal"])),
                        ["mode"] = vars.temp["mode"]
                    }
                    vars.count = 0 -- Reset variables to look for another matching resolution.
                    vars.foundRes = false
                    vars.temp = {}
                end
            end
        elseif (string.match(line, "^" .. config.display) == config.display) then -- Look for display name.
            if (string.find(line, "disconnected") ~= nil) then
                break -- Wrong display name was given.
            end
            vars.foundDisp = true
        end
    end 
    vars.handle:close()
    if (_global.modes == {}) then
        _global.modes = false
        return false
    end
end

if (config.use_xrandr == true and config.exit_drr ~= "") then
    function revertDrr()
        os.execute("xrandr --output " .. config.display .. " --mode " .. config.exit_drr .. " &")
    end
    mp.register_event("shutdown", revertDrr)
end
mp.observe_property("fps", "native", main)
mp.add_key_binding(config.osd_key, mp.get_script_name(), osdEcho, {repeatable=true})
