#if defined _hl_custom_models_included
	#endinput
#endif
#define _hl_player_models_api_included

#pragma reqlib hl_player_models_api
#if !defined AMXMODX_NOAUTOLOAD
	#pragma loadlib hl_player_models_api
#endif

/**
 * Sets a custom player model.
 *
 * @note This is not a one-time set. The plugin will remember the
 *       selected model and try to prevent attempts at changing the player
 *       model, or immediately re-apply it if necessary.
 *
 * @note Model must be precached before use.
 *
 * @note Bots that identify player's team according by his model will not work
 *       correctly, modify them to use m_szTeamName instead.
 *
 * @param id      Player index
 * @param model   Model name (e.g "models/player/barney/barney.mdl")
 *
 * @noreturn
 * @error         If the client index is not within the range of 1 to
 *                MaxClients, the client is not connected, or the 
 *                provided model is empty, an error will be thrown.
 */
native hl_set_player_model(id, const model[]);

/**
 * Restores default model of player.
 *
 * @param id	Player index
 *
 * @noreturn
 * @error       If the client index is not within the range of 1 to
 *              MaxClients, or the client is not connected, an error will be
 *              thrown.
 */
native hl_reset_player_model(id)

/**
 * Returns the team id of the player, and optionally retrieves the name of
 * the team.
 *
 * @param id            Player index
 * @param team          Buffer to store team name
 * @param len           Maximum buffer length
 *
 * @return				Team id, 0 if no team found.
 * @error               If the client index is not within the range of 1 to
 *                      MaxClients, or the client is not connected, an error will be
 *                      thrown.
 */
native hl_get_player_team(id, team[] = "", len = 0)

/**
 * Sets the player's team without killing him.
 *
 * @param id        Player index
 * @param teamid	Team id
 *
 * @noreturn
 * @error           If the client index is not within the range of 1 to
 *                  MaxClients, the client is not connected, the server
 *                  is not in teamplay, or team id provided is not valid,
 *                  an error will be thrown.
 */
native hl_set_player_team(id, teamid)
