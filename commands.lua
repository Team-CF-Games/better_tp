--[[
Commands
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

minetest.register_chatcommand("tp_vers", {
	description = S("Demander à se téléporter vers un autre joueur"),
	params = S("<nom_du_joueur> | laisser vide pour voir le message d'aide"),
	privs = {interact = true, better_tp = true},
	func = tp.tpr_send
})

minetest.register_chatcommand("tp_invite", {
	description = S("Demander à un joueur de se téléporter vers vous"),
	params = S("<nom_du_joueur> | laisser vide pour voir le message d'aide"),
	privs = {interact = true, better_tp = true},
	func = tp.tphr_send
})

minetest.register_chatcommand("tp_accepter", {
	description = S("Accepter une demande de téléportation"),
	privs = {interact = true, better_tp = true},
	func = tp.tpr_accept
})

minetest.register_chatcommand("tp_refuser", {
	description = S("Refuser une demande de téléportation"),
	privs = {interact = true, better_tp = true},
	func = tp.tpr_deny
})

minetest.register_chatcommand("tp_liste", {
	description = S("Afficher toutes les demandes de téléportation actives (envoyées ou reçues)"),
	privs = {interact = true, better_tp = true},
	func = function(player)
		tp.tpf_update_time[player] = true
		tp.list_requests(player)
	end
})

minetest.register_chatcommand("tp_bloquer", {
	description = S("Bloquer un joueur : empêche ses demandes de téléportation"),
	params = S("<nom_du_joueur> | laisser vide pour voir le message d'aide"),
	privs = {interact = true, better_tp = true},
	func = tp.tpr_mute
})

minetest.register_chatcommand("tp_debloquer", {
	description = S("Débloquer un joueur : autoriser à nouveau ses demandes"),
	params = S("<nom_du_joueur> | laisser vide pour voir le message d'aide"),
	privs = {interact = true, better_tp = true},
	func = tp.tpr_unmute
})
