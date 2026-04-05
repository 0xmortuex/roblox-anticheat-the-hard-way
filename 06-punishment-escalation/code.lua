--[[
	PunishmentService (Server ModuleScript)
	
	Central punishment handler. All AC modules funnel through this.
	Provides: Flag, AutoKick, Ban with DataStore persistence.
	
	USAGE:
	  local PS = require(path.to.PunishmentService)
	  PS.Flag(player, "reason", "source module")
	  PS.AutoKick(player, "reason", "source module")
	  PS.Ban(player, "reason", "source module")
	  PS.Unban(userId)
]]

local PunishmentService = {}

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local BanStore = DataStoreService:GetDataStore("AC_Bans_V1")

local CONFIG = {
	DRY_RUN = false,            -- true = log only, no kicks/bans
	DEBUG_PRINTS = true,
	WEBHOOK_URL = "",           -- Discord webhook (leave "" to disable)
	BAN_DURATION_HOURS = 24,    -- 0 = permanent
	FLAGS_BEFORE_KICK = 3,
	FLAGS_BEFORE_BAN = 6,
	KICK_MESSAGE = "Removed for suspicious activity.",
	BAN_MESSAGE = "Temporarily banned for suspicious activity.",
}

local FlagCounts = {}
local FlagHistory = {}

-- ═══════════════════════════════════════════
-- INTERNAL
-- ═══════════════════════════════════════════

local function Log(level, player, reason, source)
	if not CONFIG.DEBUG_PRINTS then return end
	warn(string.format("[AC %s] %s | %s | %s", level, player.Name, reason, source or "?"))
end

local function SendWebhook(player, level, reason, source, extra)
	if CONFIG.WEBHOOK_URL == "" then return end
	task.spawn(function()
		pcall(function()
			local fields = {
				{ name = "Player", value = player.Name .. " (" .. player.UserId .. ")", inline = true },
				{ name = "Level", value = level, inline = true },
				{ name = "Source", value = source or "?", inline = true },
				{ name = "Reason", value = reason },
			}
			if extra then
				for k, v in pairs(extra) do
					table.insert(fields, { name = tostring(k), value = tostring(v), inline = true })
				end
			end
			HttpService:PostAsync(CONFIG.WEBHOOK_URL, HttpService:JSONEncode({
				embeds = {{ title = "AC " .. level, color = level == "BAN" and 0xFF0000 or level == "KICK" and 0xFF8800 or 0xFFFF00, fields = fields, timestamp = DateTime.now():ToIsoDate() }}
			}))
		end)
	end)
end

local function CheckBan(player)
	local ok, data = pcall(function() return BanStore:GetAsync(tostring(player.UserId)) end)
	if not ok or not data then return false end
	if data.ExpiresAt and data.ExpiresAt > 0 and os.time() >= data.ExpiresAt then
		pcall(function() BanStore:RemoveAsync(tostring(player.UserId)) end)
		return false
	end
	local msg = CONFIG.BAN_MESSAGE
	if data.ExpiresAt and data.ExpiresAt > 0 then
		msg ..= " (" .. math.ceil((data.ExpiresAt - os.time()) / 3600) .. "h remaining)"
	end
	player:Kick(msg)
	return true
end

-- ═══════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════

function PunishmentService.Flag(player, reason, source, extra)
	local uid = player.UserId
	FlagCounts[uid] = (FlagCounts[uid] or 0) + 1
	if not FlagHistory[uid] then FlagHistory[uid] = {} end
	table.insert(FlagHistory[uid], { Reason = reason, Source = source, Time = os.clock() })

	Log("FLAG", player, reason .. " (#" .. FlagCounts[uid] .. ")", source)
	SendWebhook(player, "FLAG", reason, source, extra)

	if CONFIG.DRY_RUN then return end

	if FlagCounts[uid] >= CONFIG.FLAGS_BEFORE_BAN then
		PunishmentService.Ban(player, "Accumulated " .. FlagCounts[uid] .. " flags", source)
	elseif FlagCounts[uid] >= CONFIG.FLAGS_BEFORE_KICK then
		PunishmentService.AutoKick(player, "Accumulated " .. FlagCounts[uid] .. " flags", source)
	end
end

function PunishmentService.AutoKick(player, reason, source)
	Log("KICK", player, reason, source)
	SendWebhook(player, "KICK", reason, source)
	if CONFIG.DRY_RUN then return end
	player:Kick(CONFIG.KICK_MESSAGE .. "\n" .. reason)
end

function PunishmentService.Ban(player, reason, source)
	Log("BAN", player, reason, source)
	SendWebhook(player, "BAN", reason, source)
	if CONFIG.DRY_RUN then return end
	local expires = CONFIG.BAN_DURATION_HOURS > 0 and (os.time() + CONFIG.BAN_DURATION_HOURS * 3600) or 0
	pcall(function()
		BanStore:SetAsync(tostring(player.UserId), { Reason = reason, Source = source, BannedAt = os.time(), ExpiresAt = expires })
	end)
	player:Kick(CONFIG.BAN_MESSAGE .. "\n" .. reason)
end

function PunishmentService.GetFlagData(player) return FlagCounts[player.UserId] or 0, FlagHistory[player.UserId] or {} end
function PunishmentService.ClearFlags(player) FlagCounts[player.UserId] = 0; FlagHistory[player.UserId] = {} end
function PunishmentService.Unban(userId) pcall(function() BanStore:RemoveAsync(tostring(userId)) end) end

-- ═══════════════════════════════════════════
-- LIFECYCLE
-- ═══════════════════════════════════════════

Players.PlayerAdded:Connect(function(p) FlagCounts[p.UserId] = 0; FlagHistory[p.UserId] = {}; CheckBan(p) end)
Players.PlayerRemoving:Connect(function(p) FlagCounts[p.UserId] = nil; FlagHistory[p.UserId] = nil end)
for _, p in ipairs(Players:GetPlayers()) do FlagCounts[p.UserId] = 0; FlagHistory[p.UserId] = {} end

return PunishmentService
