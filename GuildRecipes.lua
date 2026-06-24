---@class GuildRecipes
GuildRecipes = GuildRecipes or {}

---@class GuildRecipes
local m = GuildRecipes

---@diagnostic disable-next-line: undefined-global
local lib_stub = LibStub

GuildRecipes.name = "GuildRecipes"
GuildRecipes.prefix = "GRECIPES"
GuildRecipes.tagcolor = "FFDD7744"
GuildRecipes.events = {}
GuildRecipes.debug_enabled = false

BINDING_HEADER_GUILDRECIPES = "GuildRecipes"

---@class Item
---@field id integer
---@field name string
---@field quality integer?
---@field icon string?

---@alias NotAceTimer any
---@alias TimerId number

---@class AceTimer
---@field ScheduleTimer fun( self: NotAceTimer, callback: function, delay: number, ... ): TimerId
---@field ScheduleRepeatingTimer fun( self: NotAceTimer, callback: function, delay: number, arg: any ): TimerId
---@field CancelTimer fun( self: NotAceTimer, timer_id: number )
---@field TimeLeft fun( self: NotAceTimer, timer_id: number )

---@class AceSerializer
---@field Serialize fun( self: any, ... ): string
---@field Deserialize fun( self: any, str: string ): any

---@class AceComm
---@field RegisterComm fun( self: any, prefix: string, method: function? )
---@field SendCommMessage fun( self: any, prefix: string, text: string, distribution: string, target: string?, prio: "BULK"|"NORMAL"|"ALERT"?, callbackFn: function?, callbackArg: any? )

function GuildRecipes:init()
	self.frame = CreateFrame( "Frame" )
	self.frame:SetScript( "OnEvent", function()
		if m.events[ event ] then
			m.events[ event ]()
		end
	end )

	for k, _ in pairs( m.events ) do
		m.frame:RegisterEvent( k )
	end
end

function GuildRecipes.events.ADDON_LOADED()
	if arg1 == m.name then
		---@type AceTimer
		m.ace_timer = lib_stub( "AceTimer-3.0" )

		---@type AceSerializer
		m.ace_serializer = lib_stub( "AceSerializer-3.0" )

		---@type AceComm
		m.ace_comm = lib_stub( "AceComm-3.0" )

		---@type MessageHandler
		m.msg = m.MessageHandler.new( m.ace_timer, m.ace_serializer, m.ace_comm )

		---@type TradeskillGui
		m.tsgui = m.Tradeskills.new()

		---@type SlashCommand
		m.slash_command = m.SlashCommand.new( m.name, { "gr", "GuildRecipes" } )

		m.version = GetAddOnMetadata( m.name, "Version" )
		m.info( string.format( "(v%s) Loaded", m.version ) )
	end
end

function GuildRecipes.events.PLAYER_LOGIN()
	-- Initialize DB
	GuildRecipesDB = GuildRecipesDB or {}
	m.db = GuildRecipesDB
	m.db.players = m.db.players or {}
	m.db.tradeskills = m.db.tradeskills or {}
	m.db.tradeskills_last_update = m.db.tradeskills_last_update or {}
	m.db.frame_tradeskills = m.db.frame_tradeskills or {}

	m.player = UnitName( "player" )
	m.player_class = UnitClass( "player" )
	if m.slash_command then
		m.slash_command.init()
	end

	m.tooltip = CreateFrame( "GameTooltip", "GuildRecipesTooltip", nil, "GameTooltipTemplate" )
	m.tooltip:SetOwner( WorldFrame, "ANCHOR_NONE" )

	if m.msg then
		m.update_data()
	end

	-- Wait 30 seconds after login before checking the player's own profession
	-- data and the guild roster. This is a flat delay with no retries or
	-- extra checks -- by 30 seconds in, both the skill list and the guild
	-- roster should be fully loaded.
	if m.ace_timer then
		m.ace_timer.ScheduleTimer( m, function()
			m.verify_own_tradeskills()
			m.purge_non_guild_players()
		end, 30 )
	end
end

function GuildRecipes.events.TRADE_SKILL_SHOW()
	local reverse = m.build_reverse_trade_map( GetLocale() )
	local tradeskill = reverse[ GetTradeSkillLine() ]

	if m.TRADE_SKILL_LOCALIZATION[ tradeskill ] then
		local num = GetNumTradeSkills()
		local live_recipe_ids = {}

		for i = 1, GetNumTradeSkills() do
			local _, type = GetTradeSkillInfo( i )
			if type == "header" then
				num = num - 1
			end
		end

		m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

		if m.count_recipes( m.db.tradeskills[ tradeskill ], m.player ) ~= num then
			for i = 1, GetNumTradeSkills() do
				local _, type = GetTradeSkillInfo( i )
				if type ~= "header" then
					local id, name, quality = m.parse_item_link( GetTradeSkillItemLink( i ) )
					if id then
						live_recipe_ids[ id ] = true
					end
					local item = {
						id = id,
						name = name,
						quality = quality
					}
					m.update_tradeskill_item( tradeskill, item, { m.player } )
				end
			end

			m.reconcile_tradeskill_recipes( tradeskill, live_recipe_ids )

			m.db.tradeskills_last_update[ tradeskill ] = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )
		end
	end
end

function GuildRecipes.events.CRAFT_SHOW()
	local reverse = m.build_reverse_trade_map( GetLocale() )
	local tradeskill = reverse[ GetCraftName() ]

	if tradeskill == "Enchanting" then
		local num = GetNumCrafts()
		local live_recipe_ids = {}

		m.db.tradeskills[ tradeskill ] = m.db.tradeskills[ tradeskill ] or {}

		if m.count_recipes( m.db.tradeskills[ tradeskill ], m.player ) ~= num then
			for i = 1, num do
				local id, name, quality = m.parse_item_link( GetCraftItemLink( i ) )
				if id then
					live_recipe_ids[ id ] = true
				end
				local item = {
					id = id,
					name = name,
					quality = quality
				}
				m.update_tradeskill_item( tradeskill, item, { m.player } )
			end

			m.reconcile_tradeskill_recipes( tradeskill, live_recipe_ids )

			m.db.tradeskills_last_update[ tradeskill ] = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )
		end
	end
end

function GuildRecipes.events.UNIT_INVENTORY_CHANGED()
	-- This can fire many times in quick succession (e.g. once per item when
	-- looting a stack), and each call to tsgui.update() re-scans the guild
	-- roster and redraws the visible list. Debounce so a burst of these only
	-- triggers one actual update, instead of one per event.
	if arg1 == "player" and m.tsgui.is_visible() and m.ace_timer then
		if m.inventory_update_timer then
			m.ace_timer.CancelTimer( m, m.inventory_update_timer )
		end
		m.inventory_update_timer = m.ace_timer.ScheduleTimer( m, function()
			m.inventory_update_timer = nil
			if m.tsgui.is_visible() then
				m.tsgui.update()
			end
		end, 0.5 )
	end
end

---@param tradeskill string
---@param item Item
---@param players string[]
function GuildRecipes.update_tradeskill_item( tradeskill, item, players )
	if item.id then
		local player_ids = {}
		for _, p in pairs( players ) do
			if not m.find( p, m.db.players ) then
				table.insert( m.db.players, p )
			end

			local _, player_id = m.find( p, m.db.players )
			if player_id then
				table.insert( player_ids, player_id )
			end
		end

		if m.db.tradeskills[ tradeskill ][ item.id ] then
			m.debug( string.format( "Updating %s: %s", tradeskill, item.name ) )
			if not players then
				m.debug( "ERROR, no players for: " .. tostring( item.name ) )
				return
			end

			local recipe_players = m.comma_separated_to_table( m.db.tradeskills[ tradeskill ][ item.id ].p )
			for _, p in pairs( players ) do
				local _, player_id = m.find( p, m.db.players )

				if player_id and not m.find( tostring(player_id), recipe_players ) then
					table.insert( recipe_players, player_id )
				end
			end
			m.db.tradeskills[ tradeskill ][ item.id ].p = m.table_to_comma_separated( recipe_players )
		else
			m.debug( string.format( "Adding %s: %s", tradeskill, item.name ) )

			m.db.tradeskills[ tradeskill ][ item.id ] = {
				n = item.name,
				q = item.quality,
				p = m.table_to_comma_separated( player_ids )
			}
		end
	end
end

---@param tradeskill string
---@param player string
---@return boolean removed_any
-- Strips `player`'s credit from every recipe in `tradeskill`. Removes the recipe
-- entirely if no players are left crediting it. Does not touch m.db.players or
-- the player's standing in any other tradeskill.
function GuildRecipes.remove_player_from_tradeskill( tradeskill, player )
	local removed_any = false
	local recipes = m.db.tradeskills[ tradeskill ]
	if not recipes then return false end

	local _, player_id = m.find( player, m.db.players )
	if not player_id then return false end

	for id, recipe in pairs( recipes ) do
		local players = m.comma_separated_to_table( recipe.p )
		local _, idx = m.find( tostring( player_id ), players )
		if idx then
			removed_any = true
			table.remove( players, idx )
			if getn( players ) == 0 then
				recipes[ id ] = nil
			else
				recipe.p = m.table_to_comma_separated( players )
			end
		end
	end

	return removed_any
end

---@param tradeskill string
-- Diffs the player's live, in-client recipe list for `tradeskill` against what's
-- stored under their own name, and strips any recipe they're credited with but
-- don't actually have. Catches stale data left over from a different character
-- who previously used this name (e.g. on an old server). Re-broadcasts the
-- corrected tradeskill to the guild if anything was removed.
---@param live_recipe_ids table<integer, boolean>
function GuildRecipes.reconcile_tradeskill_recipes( tradeskill, live_recipe_ids )
	local recipes = m.db.tradeskills[ tradeskill ]
	if not recipes then return end

	local _, player_id = m.find( m.player, m.db.players )
	if not player_id then return end

	local removed = 0
	for id, recipe in pairs( recipes ) do
		if not live_recipe_ids[ id ] then
			local players = m.comma_separated_to_table( recipe.p )
			local _, idx = m.find( tostring( player_id ), players )
			if idx then
				removed = removed + 1
				table.remove( players, idx )
				if getn( players ) == 0 then
					recipes[ id ] = nil
				else
					recipe.p = m.table_to_comma_separated( players )
				end
			end
		end
	end

	if removed > 0 then
		m.debug( string.format( "Reconciled %s: removed %d stale recipe(s) credited to %s", tradeskill, removed, m.player ) )
		m.db.tradeskills_last_update[ tradeskill ] = m.get_server_timestamp()
		m.msg.send_tradeskill( tradeskill )
	end
end

-- Compares the player's currently known professions against the professions
-- they're credited with in the synced data. If they're credited with recipes
-- for a profession they don't have trained at all, that's almost certainly
-- stale data from another character who previously held this name (e.g.
-- carried over from an old server). Strips it and re-syncs.
function GuildRecipes.verify_own_tradeskills()
	if not m.find( m.player, m.db.players ) then return end

	local known = m.get_known_tradeskills()
	local cleaned = {}

	for tradeskill in pairs( m.db.tradeskills ) do
		if not known[ tradeskill ] then
			if m.remove_player_from_tradeskill( tradeskill, m.player ) then
				table.insert( cleaned, tradeskill )
				m.db.tradeskills_last_update[ tradeskill ] = m.get_server_timestamp()
				m.msg.send_tradeskill( tradeskill )

				if not next( m.db.tradeskills[ tradeskill ] ) then
					m.db.tradeskills[ tradeskill ] = nil
				end
			end
		end
	end

	if getn( cleaned ) > 0 then
		m.info( string.format(
			"Found stale recipe data under your name for %s (profession%s not known on this character). Cleaned up and re-synced.",
			table.concat( cleaned, ", " ),
			getn( cleaned ) > 1 and "s" or ""
		), true )
	end
end

-- Removes a synced player from m.db.players and every tradeskill that
-- credits them, then force-resyncs any tradeskill that was changed.
-- Used by purge_non_guild_players for players who have left the guild.
---@param player string
function GuildRecipes.purge_player( player )
	local _, player_id = m.find( player, m.db.players )
	if not player_id then return false end

	for tradeskill in pairs( m.db.tradeskills ) do
		if m.remove_player_from_tradeskill( tradeskill, player ) then
			m.db.tradeskills_last_update[ tradeskill ] = m.get_server_timestamp()
			m.msg.send_tradeskill( tradeskill )

			if not next( m.db.tradeskills[ tradeskill ] ) then
				m.db.tradeskills[ tradeskill ] = nil
			end
		end
	end

	m.db.players[ player_id ] = nil
	return true
end

-- Cross-references every synced player against the current guild roster --
-- including offline members -- and purges anyone who's no longer a guild
-- member at all. Typically stale data left over from players who have since
-- left, or carried over from a different guild/server. Force-resyncs the
-- cleaned data to the guild so other members pick up the purge too.
--
-- Offline members only show up in GetGuildRosterInfo/GetNumGuildMembers if
-- SetGuildRosterShowOffline(true) is set, but that's a persistent client
-- setting that also affects the actual Guild UI tab -- so this saves the
-- player's existing preference, temporarily enables it just long enough to
-- read the roster, then restores whatever it was before.
function GuildRecipes.purge_non_guild_players()
	if not m.db or not m.db.players or not next( m.db.players ) then return end

	local was_showing_offline = GetGuildRosterShowOffline() == 1
	if not was_showing_offline then
		SetGuildRosterShowOffline( true )
		GuildRoster()
	end

	local num_members = GetNumGuildMembers()
	if num_members == 0 then
		m.debug( "Guild roster reports 0 members, skipping purge." )
		if not was_showing_offline then
			SetGuildRosterShowOffline( false )
		end
		return
	end

	local roster = {}
	for i = 1, num_members do
		local name = GetGuildRosterInfo( i )
		if name then
			roster[ name ] = true
		end
	end

	if not was_showing_offline then
		SetGuildRosterShowOffline( false )
	end

	local purged = {}
	for _, player in pairs( m.db.players ) do
		if player and not roster[ player ] then
			if m.purge_player( player ) then
				table.insert( purged, player )
			end
		end
	end

	if getn( purged ) > 0 then
		m.info( string.format(
			"Purged %d player%s no longer in the guild: %s. Re-synced to guild.",
			getn( purged ),
			getn( purged ) > 1 and "s" or "",
			table.concat( purged, ", " )
		), true )
	end
end

function GuildRecipes.update_data()
	-- If we haven't updated in the last 48 hours, request an update
	if next(m.db.tradeskills_last_update) == nil then
		m.msg.request_tradeskills()
	else
		local now = m.get_server_timestamp()
		for tradeskill, last_update in pairs( m.db.tradeskills_last_update ) do
			if now >= last_update + 172800 then
				m.msg.request_tradeskill( tradeskill )
				break
			end
		end
	end
end

---@param bag_start integer
---@param bag_end integer
---@param name string
---@return integer
function GuildRecipes.find_item_count_bag( bag_start, bag_end, name )
	local count = 0
	for bag = bag_start, bag_end do
		local slots = GetContainerNumSlots( bag )
		for slot = 1, slots do
			local _, item_count = GetContainerItemInfo( bag, slot )
			if item_count and item_count > 0 then
				local _, item_name = m.parse_item_link( GetContainerItemLink( bag, slot ) )
				if item_name == name then
					count = count + item_count
				end
			end
		end
	end
	return count
end

function GuildRecipes.fix()
	for tradeskill, recipes in pairs( m.db.tradeskills ) do
		for id, recipe in pairs( recipes ) do
			if recipe.p and type( recipe.p ) == "table" then
				local players = ""
				for _, p in pairs( recipe.p ) do
					if players ~= "" then
						players = players .. ","
					end
					players = players .. p
				end
				--	local _, pi = m.find( p, m.db.players)
				--	table.insert( players, pi )

				recipe.p = players
			end
		end
	end
end

GuildRecipes:init()
