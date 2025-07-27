-- interface.lua

local function show_main_formspec(player)
    local formspec = "size[6,4]" ..
        "label[0.5,0.5;Que voulez-vous faire ?]" ..
        "button[1,1;4,1;tp_to_player;TP vers quelqu'un]" ..
        "button[1,2;4,1;tp_to_me;TP vers moi]"
    minetest.show_formspec(player:get_player_name(), "better_tp:main", formspec)
end

local function show_input_formspec(player, mode)
    local label = mode == "to_player" and "Entrez le pseudo du joueur vers qui vous voulez vous téléporter :" or
                                              "Entrez le pseudo du joueur que vous voulez faire venir :"
    local formspec = "size[8,3]" ..
        "label[0.5,0.5;"..minetest.formspec_escape(label).."]" ..
        "field[0.5,1.5;7,1;target;;]" ..
        "button_exit[2,2.5;4,1;submit;Valider]"
    minetest.show_formspec(player:get_player_name(), "better_tp:input_"..mode, formspec)
end

local function register_interface_handlers()
    minetest.register_chatcommand("tp", {
        description = "Ouvre le menu de téléportation",
        func = function(name)
            local player = minetest.get_player_by_name(name)
            if not player then return false, "Joueur introuvable." end
            show_main_formspec(player)
            return true
        end
    })

    minetest.register_on_player_receive_fields(function(player, formname, fields)
        local name = player:get_player_name()
        if formname == "better_tp:main" then
            if fields.tp_to_player then
                show_input_formspec(player, "to_player")
            elseif fields.tp_to_me then
                show_input_formspec(player, "to_me")
            end
        elseif formname == "better_tp:input_to_player" or formname == "better_tp:input_to_me" then
            if fields.submit and fields.target and fields.target ~= "" then
                local target = fields.target
                if formname == "better_tp:input_to_player" then
                    tp.make_request(name, target, "sender")
                    minetest.chat_send_player(name, "Demande de téléportation envoyée à "..target..".")
                else
                    tp.make_request(name, target, "receiver")
                    minetest.chat_send_player(name, "Demande de téléportation envoyée à "..target..".")
                end
            else
                minetest.chat_send_player(name, "Veuillez entrer un pseudo valide.")
            end
        end
    end)
end

return {
    register = register_interface_handlers
}
