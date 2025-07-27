--[[
Functions
Copyright (C) 2014-2024 ChaosWormz and contributors

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
USA
--]]

local S = tp.S

-- Placeholders
local chatmsg, source, target,
target_coords, tpc_target_coords, old_tpc_target_coords

local spam_prevention = {}
local band = false

local muted_players = {}

local message_color = tp.message_color

local function color_string_to_number(color)
	if string.sub(color,1,1) == '#' then
		color = string.sub(color, 2)
	end
	if #color < 6 then
		local r = string.sub(color,1,1)
		local g = string.sub(color,2,2)
		local b = string.sub(color,3,3)
		color = r..r .. g..g .. b..b
	elseif #color > 6 then
		color = string.sub(color, 1, 6)
	end
	return tonumber(color, 16)
end

local message_color_number = color_string_to_number(message_color)

local function send_message(player, message)
	minetest.chat_send_player(player, minetest.colorize(message_color, message))
	if minetest.get_modpath("chat2") then
		chat2.send_message(minetest.get_player_by_name(player), message, message_color_number)
	end
end

local next_request_id = 0
local request_list = {}
local sender_list = {}
local receiver_list = {}
local area_list = {}

function tp.make_request(sender, receiver, direction)
	next_request_id = next_request_id+1
	request_list[next_request_id] = {
		time = os.time(),
		direction = direction or "receiver",
		receiver = receiver,
		sender = sender
	}

	receiver_list[receiver] = receiver_list[receiver] or {count=0}
	receiver_list[receiver][next_request_id] = true
	receiver_list[receiver].count = receiver_list[receiver].count+1

	sender_list[sender] = sender_list[sender] or {count=0}
	sender_list[sender][next_request_id] = true
	sender_list[sender].count = sender_list[sender].count+1

	return next_request_id
end

function tp.clear_request(id)
	local request = request_list[id]
	request_list[id] = nil

	sender_list[request.sender][id] = nil
	receiver_list[request.receiver][id] = nil

	sender_list[request.sender].count = sender_list[request.sender].count-1
	receiver_list[request.receiver].count = receiver_list[request.receiver].count-1

	return request
end

function tp.accept_request(id)

	local request = tp.clear_request(id)

	if request.direction == "area" then
		source = minetest.get_player_by_name(request.receiver)
		target = minetest.get_player_by_name(request.sender)
		chatmsg = S("@1 se téléporte dans vtre zone protégée @2.", request.sender, minetest.pos_to_string(tpc_target_coords[request.receiver]))
		-- If source or target are not present, abort request.
		if not source or not target then
			send_message(request.receiver, S("@1 n'est pas en ligne.", request.sender))
			return
		end
		if not tpc_target_coords[request.receiver] then
			tpc_target_coords[request.sender] = old_tpc_target_coords[request.receiver]
			tp.tpp_teleport_player(request.sender, tpc_target_coords[request.sender])

			chatmsg = S("@1 se téléporte dans votre zone protégée @2.", request.sender, minetest.pos_to_string(tpc_target_coords[request.sender]))
		else
			tp.tpp_teleport_player(request.sender, tpc_target_coords[request.receiver])
			chatmsg = S("@1 se téléporte dans votre zone protégée @2.", request.sender, minetest.pos_to_string(tpc_target_coords[request.receiver]))
		end

		send_message(request.receiver, chatmsg)
		send_message(request.sender, S("Demande acceptée !"))

		-- Avoid abusing with area requests
		target_coords = nil
	elseif request.direction == "receiver" then
		source = minetest.get_player_by_name(request.receiver)
		target = minetest.get_player_by_name(request.sender)
		chatmsg = S("@1 se téléporte vers vous.", request.sender)
		-- Could happen if either player disconnects (or timeout); if so just abort
		if not source
		or not target then
			send_message(request.receiver, S("@1 n'est pas en ligne", request.sender))
			return
		end

		tp.tpr_teleport_player()

		-- Avoid abusing with area requests
		target_coords = nil

		send_message(request.receiver, chatmsg)

		if minetest.check_player_privs(request.sender, {tp_admin = true}) == false then
			send_message(request.sender, S("Demande acceptée !"))
		else
			if tp.enable_immediate_teleport then return end

			send_message(request.sender, S("Demande acceptée"))
			return
		end
	elseif request.direction == "sender" then
		source = minetest.get_player_by_name(request.sender)
		target = minetest.get_player_by_name(request.receiver)
		chatmsg = S("Vous vous téléportez vers @1.", request.sender)
		-- Could happen if either player disconnects (or timeout); if so just abort
		if not source
		or not target then
			send_message(request.receiver, S("@1 n'est pas en ligne.", request.sender))
			return
		end

		tp.tpr_teleport_player()

		-- Avoid abusing with area requests
		target_coords = nil

		send_message(request.receiver, chatmsg)

		if minetest.check_player_privs(request.sender, {tp_admin = true}) == false then
			send_message(request.sender, S("Demande acceptée !"))
		else
			if tp.enable_immediate_teleport then return end

			send_message(request.sender, S("Demande acceptée !"))
			return
		end
	end
	return request
end

function tp.deny_request(id, own)
	local request = tp.clear_request(id)
	if own then
		send_message(request.sender, S("Vous avez refusé votre demande envoyée à @1.", request.receiver))
		send_message(request.receiver, S("@1 a refusé sa demande envoyée vers vous.", request.sender))
	else
		if request.direction == "area" then
			send_message(request.sender, S("Demande d'accès à la zone refusée."))
			send_message(request.receiver, S("Vous avez refusé la demande envoyée par @1.", request.sender))
			spam_prevention[request.receiver] = request.sender
		elseif request.direction == "receiver" then
			send_message(request.sender, S("Demande de téléportation refusée."))
			send_message(request.receiver, S("Vous avez refusé la demande envoyée par @1.", request.sender))
			spam_prevention[request.receiver] = request.sender
		elseif request.direction == "sender" then
			send_message(request.sender, S("Demande de téléportation refusée."))
			send_message(request.receiver, S("Vous avez refusé la demande envoyée par @1.", request.sender))
			spam_prevention[request.receiver] = request.sender
		end
	end
end


function tp.list_requests(playername)
	local sent_requests = tp.get_requests(playername, "sender")
	local received_requests = tp.get_requests(playername, "receiver")
	local area_requests = tp.get_requests(playername, "area")

	local formspec
	if sent_requests.count == 0 and received_requests.count == 0 and area_requests.count == 0 then
		formspec = ("size[5,2]label[1,0.3;%s:]"):format(S("Teleport Requetst"))
		formspec = formspec..("label[1,1.2;%s]"):format(S("You have no requests."))
	else
		local y = 1
		local request_list_formspec = ""
		if sent_requests.count ~= 0 then
			request_list_formspec = request_list_formspec..("label[0.2,%f;%s:]"):format(y, S("Sent by you"))
			y = y+0.7
			for request_id, _ in pairs(sent_requests) do
				if request_id ~= "count" then
					local request = request_list[request_id]
					if request.direction == "receiver" then
						request_list_formspec = request_list_formspec..("label[0.3,%f;%s]button[7,%f;1,1;deny_%s;Cancel]")
							:format(
								y, tostring(os.time()-request.time).."s ago: "..S("You are requesting to teleport to @1.", request.receiver),
								y, tostring(request_id)
							)
					elseif request.direction == "sender" then
						request_list_formspec = request_list_formspec..("label[0.3,%f;%s]button[7,%f;1,1;deny_%s;Cancel]")
							:format(
								y, tostring(os.time()-request.time).."s: "..S("You are requesting that @1 teleports to you.", request.receiver),
								y, tostring(request_id)
							)
					elseif request.direction == "area" then
						request_list_formspec = request_list_formspec..("label[0.3,%f;%s]button[7,%f;1,1;deny_%s;Cancel]")
							:format(
								y, tostring(os.time()-request.time).."s: "..S("You are requesting to teleport to @1's protected area.", request.receiver),
								y, tostring(request_id)
							)
					end
					y = y+0.8
				end
			end
		end
		if received_requests.count ~= 0 then
			y = y+0.5
			request_list_formspec = request_list_formspec..("label[0.2,%f;%s:]"):format(y, S("Sent to you"))
			y = y+0.7
			for request_id, _ in pairs(received_requests) do
				if request_id ~= "count" then
					local request = request_list[request_id]
					if request.direction == "receiver" then
						request_list_formspec = request_list_formspec..("label[0.3,%f;%s]button[6,%f;1,1;accept_%s;Accept]button[7,%f;1,1;deny_%s;Deny]")
							:format(
								y, tostring(os.time()-request.time).."s ago: "..S("@1 is requesting to teleport to you.", request.sender),
								y, tostring(request_id),
								y, tostring(request_id)
							)
					elseif request.direction == "sender" then
						request_list_formspec = request_list_formspec..("label[0.3,%f;%s]button[6,%f;1,1;accept_%s;Accept]button[7,%f;1,1;deny_%s;Deny]")
							:format(
								y, tostring(os.time()-request.time).."s ago: "..S("@1 is requesting that you teleport to them.", request.sender),
								y, tostring(request_id),
								y, tostring(request_id)
							)
					elseif request.direction == "area" then
						request_list_formspec = request_list_formspec..("label[0.3,%f;%s]button[6,%f;1,1;accept_%s;Accept]button[7,%f;1,1;deny_%s;Deny]")
							:format(
								y, tostring(os.time()-request.time).."s ago: "..S("@1 is requesting to teleport to your protected area.", request.sender),
								y, tostring(request_id),
								y, tostring(request_id)
							)
					end
					y = y+0.8
				end
			end
		end
		formspec = ("size[8,%f]label[1,0.3;%s:]"):format(math.min(y,10),S("Teleport Requests"))
			..request_list_formspec
	end

	minetest.show_formspec(playername, "teleport_request_list", formspec)

	local function update_time()
		if formspec == "" or string.find(formspec, S("You have no requests.")) then
			tp.tpf_update_time[playername] = false
			return
		end

		if tp.tpf_update_time[playername] then
			-- TODO: find a way to edit the text only and update
			-- the formspec without re-calling the function.
			tp.list_requests(playername)
		end
	end

	minetest.after(1, update_time)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "teleport_request_list" then return end

	local playername = player:get_player_name()

	local accepts = {}
	local denys = {}
	for button_name, _ in pairs(fields) do
		if string.sub(button_name, 1, 5) == "deny_" then
			table.insert(denys, tonumber(string.sub(button_name, 6)))
		elseif string.sub(button_name, 1, 7) == "accept_" then
			table.insert(accepts, tonumber(string.sub(button_name, 8)))
		end
	end
	local changes = false
	for _, id in ipairs(accepts) do
		if request_list[id] and request_list[id].receiver == playername then
			tp.accept_request(id)
			changes = true
		end
	end
	for _, id in ipairs(denys) do
		if request_list[id] and (request_list[id].sender == playername or request_list[id].receiver == playername) then
			tp.deny_request(id, request_list[id].sender == playername)
			changes = true
		end
	end

	if changes and not fields.quit then
		tp.tpf_update_time[playername] = true
		tp.list_requests(playername)
	elseif fields.quit then
		tp.tpf_update_time[playername] = false
	end
end)

function tp.get_requests(playername, party)
	local list
	if party == "sender" then
		list = sender_list
	elseif party == "receiver" then
		list = receiver_list
	elseif party == "area" then
		list = area_list
	else
		return -- Invalid party
	end
	if not list then return end

	return list[playername] or {count=0}
end

function tp.count_requests(playername, party)
	local player_list = tp.get_requests(playername, party)
	if not player_list then return 0 end

	return player_list.count or 0
end

function tp.first_request(playername, party)
	local player_list = tp.get_requests(playername, party)
	if not player_list then return end

	for request_id, _ in pairs(player_list) do
		if request_id ~= "count" then
			return request_id
		end
	end
end

local map_size = 30912
function tp.can_teleport(to)
	return to.x < map_size and to.x > -map_size and to.y < map_size and to.y > -map_size and to.z < map_size and to.z > -map_size
end

-- Teleport player to a player (used in "/tpr" and in "/tphr" command).
function tp.tpr_teleport_player()
	target_coords = source:get_pos()
	local target_sound = target:get_pos()
	target:set_pos(tp.find_free_position_near(target_coords))
	minetest.sound_play("tpr_warp", {pos = target_coords, gain = 0.5, max_hear_distance = 10})
	minetest.sound_play("tpr_warp", {pos = target_sound, gain = 0.5, max_hear_distance = 10})
	--tp.parti2(target_coords)
end

-- TPC & TPJ
function tp.tpc_teleport_player(player)
	local pname = minetest.get_player_by_name(player)
	minetest.sound_play("tpr_warp", {pos = pname:get_pos(), gain = 0.5, max_hear_distance = 10})
	pname:set_pos(tp.find_free_position_near(target_coords))
	minetest.sound_play("tpr_warp", {pos = target_coords, gain = 0.5, max_hear_distance = 10})
	--tp.parti2(target_coords)
end

-- TPP
function tp.tpp_teleport_player(player, pos)
	local pname = minetest.get_player_by_name(player)
	minetest.sound_play("tpr_warp", {pos = pname:get_pos(), gain = 0.5, max_hear_distance = 10})
	pname:set_pos(tp.find_free_position_near(pos))
	minetest.sound_play("tpr_warp", {pos = pos, gain = 0.5, max_hear_distance = 10})
	--tp.parti2(target_coords)
end

function tp.find_free_position_near(pos)
	local tries = {
		{x=1,y=0,z=0},
		{x=-1,y=0,z=0},
		{x=0,y=0,z=1},
		{x=0,y=0,z=-1},
	}
	for _,d in pairs(tries) do
		local p = vector.add(pos, d)
		local def = minetest.registered_nodes[minetest.get_node(p).name]
		if def and not def.walkable then
			return p, true
		end
	end
	return pos, false
end

function tp.parti(pos)
	minetest.add_particlespawner(50, 0.4,
		{x=pos.x + 0.5, y=pos.y, z=pos.z + 0.5}, {x=pos.x - 0.5, y=pos.y, z=pos.z - 0.5},
		{x=0, y=5, z=0}, {x=0, y=0, z=0},
		{x=0, y=5, z=0}, {x=0, y=0, z=0},
		3, 5,
		3, 5,
		false,
		"tps_portal_parti.png")
end

function tp.parti2(pos)
	minetest.add_particlespawner(50, 0.4,
		{x=pos.x + 0.5, y=pos.y + 10, z=pos.z + 0.5}, {x=pos.x - 0.5, y=pos.y, z=pos.z - 0.5},
		{x=0, y=-5, z=0}, {x=0, y=0, z=0},
		{x=0, y=-5, z=0}, {x=0, y=0, z=0},
		3, 5,
		3, 5,
		false,
		"tps_portal_parti.png")
end

-- Mutes a player from sending you teleport requests
function tp.tpr_mute(player, muted_player)
	if muted_player == "" then
		send_message(player, S("Utilisation : /tp_bloquer <nom du joueur>"))
		return
	end

	if not minetest.get_player_by_name(muted_player) then
		send_message(player, S("Aucun joueur avec ce nom. Notez que la casse compte et que le joueur doit être en ligne."))
		return
	end

	if minetest.check_player_privs(muted_player, {tp_admin = true}) and not minetest.check_player_privs(player, {server = true}) then
		send_message(player, S("tp_bloquer : Échec du blocage du joueur @1 : il a le privilège tp_admin.", muted_player))
		return
	end

	if muted_players[player] == muted_player then
		send_message(player, S("tp_bloquer : Le joueur @1 est déjà bloqué.", muted_player))
		return
	end

	muted_players[player] = muted_player
	send_message(player, S("tp_bloquer : Le joueur @1 a bien été bloqué.", muted_player))
end

-- Unmutes a player from sending you teleport requests
function tp.tpr_unmute(player, muted_player)
	if muted_player == "" then
		send_message(player, S("Utilisation : /tp_debloquer <nom du joueur>"))
		return
	end

	if not minetest.get_player_by_name(muted_player) then
		send_message(player, S("Aucun joueur avec ce nom. Notez que la casse compte et que le joueur doit être en ligne."))
		return
	end

	if muted_players[player] ~= muted_player then
		send_message(player, S("tp_bloquer : Le joueur @1 n'est pas bloqué.", muted_player))
		return
	end

	muted_players[player] = nil
	send_message(player, S("tp_bloquer : Le joueur @1 a bien été débloqué.", muted_player))
end

-- Teleport Request System
function tp.tpr_send(sender, receiver)
	if sender == receiver then
		send_message(sender, S("Vous ne pouvez pas envoyer une demande de téléportation à vous-même."))
		return
	end

	if muted_players[receiver] == sender and not minetest.check_player_privs(sender, {server = true}) then
		send_message(sender, S("Impossible d'envoyer une demande à @1 (vous avez été bloqué).", receiver))
		return
	end

	if receiver == "" then
		send_message(sender, S("Utilisation : /tp_vers <nom du joueur>"))
		return
	end

	if not minetest.get_player_by_name(receiver) then
		send_message(sender, S("Aucun joueur avec ce nom. Notez que la casse compte et que le joueur doit être en ligne."))
		return
	end

	if spam_prevention[receiver] == sender and not minetest.check_player_privs(sender, {tp_admin = true}) then
		send_message(sender, S("Attendez @1 secondes avant de pouvoir renvoyer une demande à @2.", tp.timeout_delay, receiver))

		minetest.after(tp.timeout_delay, function(sender_name, receiver_name)
			spam_prevention[receiver_name] = nil
			if band == true then return end

			if spam_prevention[receiver_name] == nil then
				send_message(sender_name, S("Vous pouvez maintenant envoyer des demandes de téléportation à @1.", receiver_name))
				band = true
			end
		end, sender, receiver)
	else
		-- Compatibilité avec beerchat
		if minetest.get_modpath("beerchat") and not minetest.check_player_privs(sender, {tp_admin = true}) then
			if receiver == "" then
				send_message(sender, S("Utilisation : /tp_vers <nom du joueur>"))
				return
			end

			if not minetest.get_player_by_name(receiver) then
				send_message(sender, S("Aucun joueur avec ce nom. Notez que la casse compte et que le joueur doit être en ligne."))
				return
			end

			local player_receiver = minetest.get_player_by_name(receiver)
			if player_receiver:get_meta():get_string("beerchat:muted:" .. sender) == "true" then
				send_message(sender, S("Vous n'êtes pas autorisé à envoyer des demandes car vous êtes bloqué."))
				return
			end
		end

		if minetest.check_player_privs(sender, {tp_admin = true}) and tp.enable_immediate_teleport then
			if receiver == "" then
				send_message(sender, S("Utilisation : /tp_vers <nom du joueur>"))
				return
			end

			if not minetest.get_player_by_name(receiver) then
				send_message(sender, S("Aucun joueur avec ce nom. Notez que la casse compte et que le joueur doit être en ligne."))
				return
			end

			local id = tp.make_request(sender, receiver, "receiver")
			tp.accept_request(id)
			return
		end

		if receiver == "" then
			send_message(sender, S("Utilisation : /tp_vers <nom du joueur>"))
			return
		end

		if not minetest.get_player_by_name(receiver) then
			send_message(sender, S("Aucun joueur avec ce nom. Notez que la casse compte et que le joueur doit être en ligne."))
			return
		end

		if minetest.get_modpath("gamehub") then -- Compatibilité avec gamehub (NON TESTÉ)
			if gamehub.players[receiver] then
				send_message(sender, S("Demande de téléportation refusée, le joueur est dans le gamehub !"))
				return
			end
		end

		send_message(receiver, S("@1 vous demande de venir vous téléporter. Tapez /tp_accepter pour accepter.", sender))
		send_message(sender, S("Demande de téléportation envoyée ! Elle expirera dans @1 secondes.", tp.timeout_delay))

		local tp_id = tp.make_request(sender, receiver, "receiver")

		minetest.after(tp.timeout_delay, function(id)
			if request_list[id] then
				local request = tp.clear_request(id)

				send_message(request.sender, S("La demande a expiré."))
				send_message(request.receiver, S("La demande a expiré."))
				return
			end
		end, tp_id)
	end
end

function tp.tphr_send(sender, receiver)
	-- Disallow entering inaccessible areas. (Teleportation includes a position offset of 1)
	if sender == receiver then
		send_message(sender, S("Vous ne pouvez pas vous envoyer de demande a vous même !"))
		return
	end

	-- Check if the sender is muted
	if muted_players[receiver] == sender and not minetest.check_player_privs(sender, {server = true}) then
		send_message(sender, S("Vous ne pouvez pas envoyer de demande à @1 (vous avez été bloqué)", receiver))
		return
	end

	if receiver == "" then
		send_message(sender, S("Utilisation : /tp_invite <nom du joueur>."))
		return
	end

	if not minetest.get_player_by_name(receiver) then
		send_message(sender, S("Aucun joueur de ce nom. Notez que le joueur doit être en ligne, et attention aux majuscules."))
		return
	end

	-- Spam prevention
	if spam_prevention[receiver] == sender and not minetest.check_player_privs(sender, {tp_admin = true}) then
		send_message(sender, S("Attendez @1 secondes avant de pouvoir envoyer de nouvelles demandes à @2.", tp.timeout_delay, receiver))

		minetest.after(tp.timeout_delay, function(sender_name, receiver_name)
			spam_prevention[receiver_name] = nil
			if band == true then return end

			if spam_prevention[receiver_name] == nil then
				send_message(sender_name, S("Vous pouvez maintenant envoyer des demandes à @1.", receiver_name))
				band = true
			end
		end, sender, receiver)
	else
	-- Compatibility with beerchat
		if minetest.get_modpath("beerchat") and not minetest.check_player_privs(sender, {tp_admin = true}) then
			if receiver == "" then
				send_message(sender, S("Utilisation : /tp_invite <nom du joueur>."))
				return
			end

			if not minetest.get_player_by_name(receiver) then
				send_message(sender, S("Aucun joueur de ce nom. Notez que le joueur doit être en ligne, et attention aux majuscules"))
				return
			end

			local player_receiver = minetest.get_player_by_name(receiver)
			if player_receiver:get_meta():get_string("beerchat:muted:" .. sender) == "true" then
				send_message(sender, S("Vous ne pouvez pas envoyer de demande car vous êts bloqué !"))
				return
			end
		end

		if minetest.check_player_privs(sender, {tp_admin = true}) and tp.enable_immediate_teleport then
			if receiver == "" then
				send_message(sender, S("Utilisation : /tp_invite <nom du joueur>."))
				return
			end

			if not minetest.get_player_by_name(receiver) then
				send_message(sender, S("Aucun joueur de ce nom. Notez que le joueur doit être en ligne, et attention aux majuscules"))
				return
			end

			tp.tphr_list[receiver] = sender
			tp.tpr_accept(receiver)
			send_message(sender, S("@1 se téléporte vers vous.", receiver))
			return
		end

		if receiver == "" then
			send_message(sender, S("Utilisation : /tp_invite <nom du joueur>"))
			return
		end

		if not minetest.get_player_by_name(receiver) then
			send_message(sender, S("Aucun joueur de ce nom. Notez que le joueur doit être en ligne et attention aux majuscules."))
			return
		end

		if minetest.get_modpath("gamehub") then -- Compatibility with gamehub (UNTESTED)
			if gamehub.players[receiver] then
				send_message(sender, S("Demande de téléportation refusée, le joueur est dans le gamehub."))
				return
			end
		end

		send_message(receiver, S("@1 souhaite se téléporter vers vous. Faites /tp_accepter pour accepter ou /tp_refuser pour refuser.", sender))
		send_message(sender, S("Demande envoyée ! Elle expire dans @1 secondes..", tp.timeout_delay))

		local tp_id = tp.make_request(sender, receiver, "sender")

		-- Teleport timeout delay
		minetest.after(tp.timeout_delay, function(id)
			if request_list[id] then
				local request = tp.clear_request(id)

				send_message(request.sender, S("Temps  écoulé."))
				send_message(request.receiver, S("Temps écoulé."))
				return
			end
		end, tp_id)
	end
end



function tp.tpr_deny(name)
	if tp.count_requests(name, "sender") == 0 and tp.count_requests(name, "receiver") == 0 then
		send_message(name, S("Utilisation : /tp_refuser permet de refuser les demandes de téléportation."))
		return
	end

	if (tp.count_requests(name, "sender") + tp.count_requests(name, "receiver")) > 1 then
		-- Show formspec for decision
		tp.list_requests(name)
		tp.tpf_update_time[name] = true
		return
	end

	local received_request = tp.first_request(name, "receiver")
	if received_request then
		tp.deny_request(received_request, false)
		return
	end

	local sent_request = tp.first_request(name, "sender")
	if sent_request then
		tp.deny_request(sent_request, true)
		return
	end
end

-- Teleport Accept Systems
function tp.tpr_accept(name)
	-- Check to prevent constant teleporting
	if tp.count_requests(name, "receiver") == 0 then
		send_message(name, S("Utilisation : /tp_accepter permet d'accepter des demandes de téléportation."))
		return
	end

	if tp.count_requests(name, "receiver") > 1 then
		-- Show formspec for decision
		tp.list_requests(name)
		tp.tpf_update_time[name] = true
		return
	end

	local received_request = tp.first_request(name, "receiver")

	if not received_request then return end -- This shouldn't happen, but who knows

	tp.accept_request(received_request)
end

