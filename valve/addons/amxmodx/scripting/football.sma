#include <amxmisc>
#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <fun>
#include <hamsandwich>
#include <hl_player_models_api>
#include <hlstocks>
#include <msgstocks>

#define PLUGIN  "Football N' Guns"
#define VERSION "1.2"
#define AUTHOR  "rtxA"

#pragma semicolon 1

#define IsPlayer(%0) (%0 > 0 && %0 <= MaxClients)

// --------------------------------- Sounds ---------------------------------

new const SND_GOAL[] 	= "football/goal.wav";
new const SND_BOO[] 	= "football/boo.wav";
new const SND_CHEER[] 	= "football/cheer.wav";
new const SND_CHANT[] 	= "football/chant.wav";
new const SND_QDAMAGE[] = "football/qdamage.wav";
new const SND_SPAWN[]	= "football/r_tele1.wav";
new const SND_BUZZ[]	= "ambience/alienlaser1.wav";	
new const SND_PICK_BALL[] = "football/pick_ball.wav";
new const SND_DROP_BALL[] = "football/drop_ball.wav";

// countdown sounds
new const SND_COUNT[][] = {
	"fvox/one.wav",
	"fvox/two.wav",
	"fvox/three.wav",
	"fvox/four.wav",
	"fvox/five.wav",
};

// --------------------------------- Models ---------------------------------

new const MDL_BALL[]	   = "models/football/ball.mdl";
new const MDL_CIVILIAN[]   = "models/football/tfcivilian.mdl";
new const MDL_SOLDIER[]    = "models/football/tfsoldier2.mdl";
new const MDL_SCOUT[]      = "models/football/tfscout_fixed.mdl";
new const MDL_MEDIC[]      = "models/football/tfmedic2.mdl";
new const MDL_V_UMBRELLA[] = "models/football/v_umbrella.mdl";
new const MDL_P_UMBRELLA[] = "models/football/p_umbrella.mdl";

// --------------------------------- Sprites ---------------------------------

new const SPR_BEAM[] = "sprites/laserbeam.spr";

// --------------------------------- Entities name ---------------------------------

new const TNAME_AREALIMITS[]  		= "fb_arealimits";
new const TNAME_BALL[]             	= "fb_ball";
new const TNAME_WALL[]             	= "fb_wall";
new const TNAME_FIELDLIMITS[]      	= "fb_fieldlimits";
new const TNAME_GOALKEEPER_BLUE[]  	= "fb_goalkeeper_blue";
new const TNAME_GOALKEEPER_RED[]   	= "fb_goalkeeper_red";
new const TNAME_GOALAREA_BLUE[]     = "fb_goalarea_blue";
new const TNAME_GOALAREA_RED[]     	= "fb_goalarea_red";

// --------------------------------- Gamemode Attributes ---------------------------------

#define GOAL_TEAM_POINTS 		1
#define GOAL_PLAYER_POINTS 		10
#define CIVILIAN_KILL_POINTS 	5

#define BALL_DELAY_TIME 1.5

// ------------------------------------------------------------------

#define BALL_SEQ_NOTCARRIED 0
#define BALL_SEQ_CARRIED 1

#define BLU_COLOR_STR "140"
#define RED_COLOR_STR "0"

enum (+= 100) {
	TASK_ROUNDCOUNTDOWN = 1959,
	TASK_PUTINSERVER,
	TASK_DISPLAYSCORE,
	TASK_PLAYERTRAIL
} 

enum {
	TEAM_NONE = 0,
	TEAM_BLUE,
	TEAM_RED
};

enum {
	FB_CLASS_NONE = 0,
	FB_CLASS_SCOUT,
	FB_CLASS_SOLDIER,
	FB_CLASS_MEDIC,
	FB_CLASS_CIVILIAN // goalkeeper
};

// players lang
new g_LangPlayers[MAX_PLAYERS + 1][16];

// team names and score
new g_TeamNames[HL_MAX_TEAMS][HL_MAX_TEAMNAME_LENGTH];
new g_TeamScore[2];

// gamemode
new g_RoundCountDown;

// global entities
new g_EntBall;
new g_EntBallPlaceHolder;
new g_EntDividingWall;
new g_EntGoalKeeperBlue;
new g_EntGoalKeeperRed;

// hud handlers
new g_TeamScoreHudSync;
new g_HudCtfMsgSync;

// sprite beam (used in player trail when he has the ball)
new g_SprBeam;

public plugin_precache() {
	precache_model(MDL_CIVILIAN);
	precache_model(MDL_SOLDIER);
	precache_model(MDL_SCOUT);
	precache_model(MDL_MEDIC);
	precache_model(MDL_BALL);
	precache_model(MDL_V_UMBRELLA);
	precache_model(MDL_P_UMBRELLA);

	precache_sound(SND_CHANT);
	precache_sound(SND_GOAL);
	precache_sound(SND_BOO);
	precache_sound(SND_CHEER);
	precache_sound(SND_QDAMAGE);
	precache_sound(SND_SPAWN);
	precache_sound(SND_PICK_BALL);
	precache_sound(SND_DROP_BALL);

	g_SprBeam = precache_model(SPR_BEAM);
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);

	register_forward(FM_GetGameDescription, "OnGetGameDescription");

	register_dictionary("football.txt");

	// cache models from teamlist for set team score without hardcoding team names
	GetTeamListModels(g_TeamNames, sizeof(g_TeamNames));

	g_HudCtfMsgSync = CreateHudSyncObj();
	g_TeamScoreHudSync = CreateHudSyncObj();

	set_task_ex(1.0, "TaskDisplayScore", TASK_DISPLAYSCORE, _, _, SetTask_Repeat);

	register_clcmd("say !team", "CmdTeamMenu");
	register_clcmd("say !class", "CmdClassMenu");

	register_concmd("sv_restart", "CmdRestartGame", ADMIN_KICK);
	register_concmd("sv_restartround", "CmdRestartRound", ADMIN_KICK);

	// field
	register_touch("trigger_teleport", "player", "OnTriggerTeleportTouch");
	register_touch("trigger_push", "player", "OnTriggerPushTouch");

	// goalarea
	register_touch("trigger_multiple", "player", "OnTriggerMultipleTouch");
	register_touch("trigger_multiple", "ball", "OnTriggerMultipleTouch");

	// ball
	register_touch("ball", "player", "OnBallTouch");
	register_clcmd("drop", "CmdDrop");

	// player hooks
	RegisterHamPlayer(Ham_Spawn, "OnPlayerSpawn_Post", true);
	RegisterHamPlayer(Ham_TakeDamage, "OnPlayerTakeDamage_Pre");
	RegisterHamPlayer(Ham_Killed, "OnPlayerKilled_Post", true);
	RegisterHam(Ham_Touch, "weaponbox", "OnWeaponBoxTouch_Pre");

	// Quad damage sound for civilian
	RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_crowbar", "OnCrowbarPrimaryAttack_Pre");
	RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_crowbar", "OnCrowbarPrimaryAttack_Post", true);

	register_clcmd("spectate", "CmdSpectate");

	InitFootball();
	RoundPreStart();
}

// Game mode name that should be displayed in server browser
public OnGetGameDescription() {
	forward_return(FMV_STRING, PLUGIN + " " + VERSION);
	return FMRES_SUPERCEDE;
}

public OnCrowbarPrimaryAttack_Pre(this, anim) {
	new id = pev(this, pev_owner);

	if (GetPlayerClass(id) == FB_CLASS_CIVILIAN) {
		// reset animation before sent
		set_pev(id, pev_weaponanim, 1);
	}
}

public OnCrowbarPrimaryAttack_Post(this, anim) {
	new id = pev(this, pev_owner);
	
	if (GetPlayerClass(id) == FB_CLASS_CIVILIAN) {
		switch (pev(id, pev_weaponanim)) {
			case 6, 8: {}
			default: emit_sound(id, CHAN_ITEM, SND_QDAMAGE, VOL_NORM, ATTN_NORM, 0, 95 + random_num(0, 31));
		}
	}
}


public OnWeaponBoxTouch_Pre(this) {
	// Remove weapons and leavy only ammo
	WeaponBox_RemoveWeapons(this);
	return HAM_IGNORED;
}

/* Player functions
 */

public OnPlayerSpawn_Post(id) {
	// fix issue where player can change his team with the vgui team menu
	if (__get_user_team(id) != GetPlayerTeam(id)) {
		SetPlayerTeam(id, __get_user_team(id));
	}

	switch (GetPlayerTeam(id)) {
		case TEAM_BLUE: {
			if (GetPlayerClass(id) == FB_CLASS_CIVILIAN) {
				TeleportToSpawn(id, g_EntGoalKeeperBlue);
			}
		} case TEAM_RED: {
			if (GetPlayerClass(id) == FB_CLASS_CIVILIAN) {
				TeleportToSpawn(id, g_EntGoalKeeperRed);
			}
		}
	}

	SetClassAtribbutes(id);
	DrawFlagIcon(id, true, GetPlayerTeam(id));
	SpeakSnd(id, SND_SPAWN);
}

public OnPlayerTakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagetype) {
	if (GetPlayerClass(attacker) == FB_CLASS_CIVILIAN) {
		if (get_user_weapon(attacker) == HLW_CROWBAR) {
			SetHamParamFloat(4, 500.0);
			SetHamParamInteger(5, DMG_ALWAYSGIB); // always gib human
			return HAM_IGNORED;
		}
	}

	if (GetPlayerClass(victim) == FB_CLASS_CIVILIAN) {
		// if civilian tries to change his team, kill him
		if (!IsPlayer(attacker) && damage == 10000.0 || damage == 900.0) {
			set_user_godmode(victim, false);
			return HAM_IGNORED;
		}
	}

	return HAM_IGNORED;
}

public OnPlayerKilled_Post(victim, attacker, shouldGib) {
	// remove effects
	set_user_rendering(victim, kRenderFxNone, 0, 0, 0, kRenderNormal, 0);

	if (GetBallOwner() == victim) {
		DropBall();
	}

	if (GetPlayerClass(attacker) == FB_CLASS_CIVILIAN) {
		if (GetPlayerTeam(attacker) != GetPlayerTeam(victim))
			hl_set_user_frags(attacker, hl_get_user_frags(attacker) + CIVILIAN_KILL_POINTS);
	}
}

public client_infochanged(id) {
	// Keep updated translated team names in scoreboard
	new lang[16];
	get_user_info(id, "lang", lang, charsmax(lang));

	if (!equal(lang, g_LangPlayers[id])) {
		get_user_info(id, "lang", g_LangPlayers[id], charsmax(g_LangPlayers[]));
		UpdateTeamNames(id);
	}

	// Keep colormap everytime player changes his setinfo
	new colorTeam[32];
	switch (GetPlayerTeam(id)) {
		case TEAM_BLUE: copy(colorTeam, charsmax(colorTeam), BLU_COLOR_STR);
		case TEAM_RED: copy(colorTeam, charsmax(colorTeam), RED_COLOR_STR);
		case TEAM_NONE: return;
	}

	engfunc(EngFunc_SetClientKeyValue, id, engfunc(EngFunc_GetInfoKeyBuffer, id), "topcolor", colorTeam);
	engfunc(EngFunc_SetClientKeyValue, id, engfunc(EngFunc_GetInfoKeyBuffer, id), "bottomcolor", colorTeam);
}

public TaskPutInServer(taskid) {
	new id = taskid - TASK_PUTINSERVER;

	get_user_info(id, "lang", g_LangPlayers[id], charsmax(g_LangPlayers[]));

	UpdateTeamNames(id);
	UpdateTeamScore(id);

	// bots don't know how to select team
	if (is_user_bot(id)) {
		new team = id % 2 ? TEAM_BLUE : TEAM_RED;
		new class = random_num(FB_CLASS_SCOUT, FB_CLASS_CIVILIAN);

		if (class == FB_CLASS_CIVILIAN && GetPlayersNumByClass(team, class))
			class = random_num(FB_CLASS_SCOUT, FB_CLASS_MEDIC);

		ChangePlayerTeam(id, team);
		SetPlayerTeam(id, team);
		SetPlayerClass(id, class);

		return;
	}

	// increase display time of center messages
	client_cmd(id, "scr_centertime 3");

	hl_set_user_spectator(id, true);

	DisplayTeamMenu(id);
}

public client_putinserver(id) {
	set_task(0.1, "TaskPutInServer", TASK_PUTINSERVER + id);
}

public client_disconnected(id) {
	if (!pev_valid(id)) {
		SetPlayerTeam(id, TEAM_NONE);
		SetPlayerClass(id, FB_CLASS_NONE);
	}

	if (GetBallOwner() == id) {
		DropBall();
	}

	g_LangPlayers[id][0] = '^0';
}

/* =============================== */

public InitFootball() {
	g_EntBallPlaceHolder = find_ent_by_tname(0, TNAME_BALL);
	g_EntDividingWall = find_ent_by_tname(0, TNAME_WALL);
	g_EntGoalKeeperBlue = find_ent_by_tname(0, TNAME_GOALKEEPER_BLUE);
	g_EntGoalKeeperRed = find_ent_by_tname(0, TNAME_GOALKEEPER_RED);
	g_EntBall = SpawnBall();
}

public RoundPreStart() {
	SetDividingWall(true);
	CallRoundCountDown();
}

public CallRoundCountDown() {
	g_RoundCountDown = 15;
	RoundCountDown();
}

public RoundCountDown() {
	// little hack to show message much longer
	if (g_RoundCountDown == 10) {
		client_print(0, print_center, "%l", "FB_MATCHSTART", 10);
	}

	if (g_RoundCountDown == 0) {
		RoundStart();
		client_print(0, print_center, "%l", "FB_MATCHSTARTED", g_RoundCountDown);
		return;
	} else if (g_RoundCountDown <= 5) {
		client_print(0, print_center, "%l", "FB_STARTS", g_RoundCountDown);
		PlaySound(0, SND_COUNT[g_RoundCountDown - 1]);
	}

	g_RoundCountDown--;

	set_task(1.0, "RoundCountDown", TASK_ROUNDCOUNTDOWN);
}

public RoundStart() {
	PlaySound(0, SND_CHANT);
	SetDividingWall(false);
}

public RoundRestart() {
	new players[MAX_PLAYERS], numPlayers;
	get_players_ex(players, numPlayers, GetPlayers_ExcludeHLTV);

	new plr;
	for (new i; i < numPlayers; i++) {
		plr = players[i];
		if (GetPlayerTeam(plr) != TEAM_NONE && GetPlayerClass(plr) != FB_CLASS_NONE) {
			hl_user_spawn(plr);
		}
	}

	ReturnBallToBase();
	remove_task(TASK_ROUNDCOUNTDOWN);
	RoundPreStart();
}

public CmdRestartGame(id, level, cid) {
	if (!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED;

	// reset players score
	for (new i = 1; i <= MaxClients; i++) {
		if (is_user_connected(i))
			hl_set_user_score(i, 0, 0);
	}

	// reset team score
	for (new i; i < sizeof(g_TeamScore); i++) {
		g_TeamScore[i] = 0;
	}

	UpdateTeamScore();

	RoundRestart();
	client_print(0, print_center, "%l", "FB_MATCHRESTART");

	return PLUGIN_HANDLED;
}

public CmdRestartRound(id, level, cid) {
	if (!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED;

	RoundRestart();
	client_print(0, print_center, "%l", "FB_MATCHRESTART");

	return PLUGIN_HANDLED;
}


// to do: activate auto team balance when there's at least 4 players
// also: if new player didn't select team for 15 seconds, do it automatically
// probably he doesn't know how to do it or menu has never show up...
public CmdSpectate(id) {
	// Don't let spectators join the game if they don't have selected a team and class
	if (hl_get_user_spectator(id)) {
		if (GetPlayerTeam(id) == TEAM_NONE || GetPlayerClass(id) == FB_CLASS_NONE)
			return PLUGIN_HANDLED;
		hl_user_spawn(id);
	} else {
		if (GetBallOwner() == id)
			DropBall();

		// reset team and class
		SetPlayerTeam(id, TEAM_NONE);
		SetPlayerClass(id, FB_CLASS_NONE);

		// remove effects
		set_user_rendering(id, kRenderFxNone, 0, 0, 0, kRenderNormal, 0);
		DisplayTeamMenu(id);
	}
	
	return PLUGIN_CONTINUE;
}

/* Ball functions
*/

public CmdDrop(id, level, cid) {
	if (GetBallOwner() == id)
		DropBall();

	return PLUGIN_HANDLED;
}

public SpawnBall() {
	new ent = create_entity("info_target");

	set_pev(ent, pev_classname, "ball");

	new Float:origin[3];
	pev(g_EntBallPlaceHolder, pev_origin, origin);

	entity_set_model(ent, MDL_BALL);
	entity_set_size(ent, Float:{ -8.0, -8.0, 0.0 }, Float:{ 8.0, 8.0, 8.0 });

	set_pev(ent, pev_origin, origin);
	set_pev(ent, pev_movetype, MOVETYPE_FLY);
	set_pev(ent, pev_solid, SOLID_TRIGGER);
	set_pev(ent, pev_sequence, BALL_SEQ_NOTCARRIED);
	set_pev(ent, pev_framerate, 1.0);

	// set glow
	set_ent_rendering(ent, kRenderFxGlowShell, 255, 255, 0, kRenderNormal, 30);

	return ent;
}

public OnBallTouch(touched, toucher) {
	if (GetBallNextTouch(touched) >= get_gametime() && GetBallLastOwner() == toucher)
		return PLUGIN_HANDLED;

	if (!is_user_alive(toucher) || GetPlayerClass(toucher) == FB_CLASS_CIVILIAN)
		return PLUGIN_HANDLED;

	EquipBall(toucher);

	return PLUGIN_CONTINUE;
}

public ReturnBallToBase() {
	new Float:origin[3];
	pev(g_EntBallPlaceHolder, pev_origin, origin);

	entity_set_origin(g_EntBall, origin);
	UnattachBallFromPlayer();
	set_pev(g_EntBall, pev_movetype, MOVETYPE_FLY);

	set_pev(g_EntBall, pev_solid, SOLID_TRIGGER);

	entity_set_size(g_EntBall, Float:{ 4.0, 4.0, 0.0 }, Float:{ 4.0, 4.0, 4.0 });

	create_teleport_splash(g_EntBall);

	SetBallNextTouch(g_EntBall, BALL_DELAY_TIME);
}

public DropBall() {
	new ent = g_EntBall;
	new id = GetBallOwner();

	UnattachBallFromPlayer();
	set_pev(g_EntBall, pev_movetype, MOVETYPE_TOSS);

	SetBallLastOwner(id);

	if (is_user_alive(id)) { // drop it where player points
		new Float:velocity[3];
		velocity_by_aim(id, 400, velocity);
		set_pev(ent, pev_velocity, velocity);
	} else { // release it from player's position
		new Float:origin[3];
		pev(id, pev_origin, origin);
		entity_set_origin(ent, origin);
		new Float:velocity[3] = {0.0, 0.0, 500.0};
		set_pev(ent, pev_velocity, velocity);
	}

	entity_set_size(ent, Float:{0.0, 0.0, 0.0}, Float:{0.0, 0.0, 0.0}); // collisions will work as expected with no size (strange)

	SetBallNextTouch(ent, BALL_DELAY_TIME); // i think only same player has to wait, other player should pick up the ball inmediatly
	set_pev(ent, pev_solid, SOLID_TRIGGER);

	PlaySound(id, SND_DROP_BALL);

	CustomHudMsg(id, "FB_LOSTBALL");
}

public EquipBall(id) {
	AttachBallToPlayer(id);
	CustomHudMsg(id, "FB_HASBALL");
	PlaySound(id, SND_PICK_BALL);
}

public AttachBallToPlayer(id) {
	set_pev(g_EntBall, pev_movetype, MOVETYPE_FOLLOW);
	set_pev(g_EntBall, pev_aiment, id);
	set_pev(g_EntBall, pev_sequence, BALL_SEQ_CARRIED);
	set_pev(g_EntBall, pev_solid, SOLID_NOT);

	ColorTeamTrail(id);
	set_task_ex(2.0, "TaskPlayerTrail", TASK_PLAYERTRAIL + id, .flags = SetTask_Repeat);
}

public TaskPlayerTrail(taskid) {
	new id = taskid - TASK_PLAYERTRAIL;
	ColorTeamTrail(id);
}

public UnattachBallFromPlayer() {
	new id = GetBallOwner();
	remove_task(TASK_PLAYERTRAIL + id);
	kill_trail_msg(id);

	set_pev(g_EntBall, pev_aiment, 0);
	set_pev(g_EntBall, pev_sequence, BALL_SEQ_NOTCARRIED);
}

public SetBallNextTouch(ent, Float:time) {
	set_pev(ent, pev_fuser1, get_gametime() + time);
}

public Float:GetBallNextTouch(ent) {
	return entity_get_float(ent, EV_FL_fuser1);
}

/* ======================
*/



/* Goalarea
*/

public OnTriggerMultipleTouch(touched, toucher) {
	new targetname[32]; // name of this trigger_multiple
	pev(touched, pev_targetname, targetname, charsmax(targetname));

	new classname[32]; // classname of toucher (probably a player)
	pev(toucher, pev_classname, classname, charsmax(classname));
	
	new teamGoalArea;
	if (strcmp(targetname, TNAME_GOALAREA_BLUE) == 0) {
		teamGoalArea = TEAM_BLUE;
	} else if (strcmp(targetname, TNAME_GOALAREA_RED) == 0) {
		teamGoalArea = TEAM_RED;
	}

	// if goal area is touched
	if (teamGoalArea > 0) {
		if (equal(classname, "player")) {
			if (GetBallOwner() == toucher) {
				new goalFromTeam = GetOppositeTeam(teamGoalArea);

				AddPointsToScore(goalFromTeam, GOAL_TEAM_POINTS);

				// update team score in all players
				UpdateTeamScore();

				PlaySound(0, SND_GOAL);

				client_print(0, print_center, "%l^n^n%l", goalFromTeam == TEAM_BLUE ? "FB_GOALBLUE" : "FB_GOALRED", "FB_SCORER", toucher);
				
				// Fade user screen with color of winner
				if (goalFromTeam == TEAM_BLUE) {
					fade_user_screen(0, 1.0, 1.0, ScreenFade_FadeIn, 0, 0, 255, 75);
				} else if (goalFromTeam == TEAM_RED) {
					fade_user_screen(0, 1.0, 1.0, ScreenFade_FadeIn, 255, 0, 0, 75);
				}

				// own goal
				if (GetPlayerTeam(toucher) == teamGoalArea) {
					PlaySound(0, SND_BOO);
					hl_set_user_frags(toucher, hl_get_user_frags(toucher) - GOAL_PLAYER_POINTS);
					client_print(toucher, print_center, "%l", "FB_OWNGOAL");
				} else { // good goal
					PlaySound(0, SND_CHEER);
					hl_set_user_frags(toucher, hl_get_user_frags(toucher) + GOAL_PLAYER_POINTS);
				}
				
				RoundRestart();
			}
		}
	}

	return PLUGIN_CONTINUE;
}

public GetOppositeTeam(team) {
	switch (team) {
		case TEAM_BLUE: return TEAM_RED;
		case TEAM_RED: return TEAM_BLUE;
		case TEAM_NONE: return TEAM_NONE;
	}
	return 0;
}

/* ===========================
*/


/* Manage touch function from field lines
*/

public OnTriggerPushTouch(touched, toucher) {
	new targetname[32];
	pev(touched, pev_targetname, targetname, charsmax(targetname));

	strtolower(targetname);

	if (!equal(targetname, TNAME_FIELDLIMITS)) {
		return PLUGIN_CONTINUE;
	}

	if (is_user_alive(toucher)) {
		// don't let anyone with the ball to get out from the field
		if (toucher == GetBallOwner()) {
			return PLUGIN_CONTINUE;
		}

		if (GetPlayerClass(toucher) != FB_CLASS_CIVILIAN) {
			return PLUGIN_HANDLED;
		}
	}

	return PLUGIN_CONTINUE;
}

public OnTriggerTeleportTouch(touched, toucher) {
	new targetname[32];
	pev(touched, pev_targetname, targetname, charsmax(targetname));

	strtolower(targetname);

	if (!equal(targetname, TNAME_AREALIMITS)) {
		return PLUGIN_CONTINUE;
	}

	if (is_user_alive(toucher)) {
		if (GetPlayerClass(toucher) != FB_CLASS_CIVILIAN) {
			return PLUGIN_HANDLED;
		}
		// warning sound, goalkeeper can't go out from his area
		SpeakSnd(toucher, SND_BUZZ);
	}

	return PLUGIN_CONTINUE;
}

/* ===========================
*/


/* Display messages
*/

public TaskDisplayScore(taskid) {
	DisplayScore();
}

// maybe change colors for 5 seconds when a goal is made
public DisplayScore() {
	set_hudmessage(205, 80, 255, -1.0, -0.02, 1, 0.01, 600.0, 0.01, 0.01);
	ShowSyncHudMsg(0, g_TeamScoreHudSync, "Football N' Guns^n[%l:%02d] - [%l:%02d]", "FB_TEAM_BLUE", GetTeamScore(TEAM_BLUE), "FB_TEAM_RED", GetTeamScore(TEAM_RED));
}

/* Team and Class Menu
*/

public CmdTeamMenu(id) {
	DisplayTeamMenu(id);
	return PLUGIN_CONTINUE;
}

public DisplayTeamMenu(id) {
	new menu = menu_create(fmt("%L", id, "FB_TEAMMENU"), "HandlerTeamMenu");
	menu_additem(menu, fmt("%L", id, "FB_TEAM_BLUE"));
	menu_additem(menu, fmt("%L", id, "FB_TEAM_RED"));
	menu_setprop(menu, MPROP_NOCOLORS, true);
	//menu_addblank(menu, false);
	//menu_additem(menu, fmt("%l", "FB_RANDOM"));

	menu_display(id, menu);
}

public HandlerTeamMenu(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	switch (item) {
		case 0: {
			ChangePlayerTeam(id, TEAM_BLUE, true);
			SetPlayerTeam(id, TEAM_BLUE);
			set_user_info(id, "topcolor", BLU_COLOR_STR);
			set_user_info(id, "bottomcolor", BLU_COLOR_STR);

		}
		case 1: {
			ChangePlayerTeam(id, TEAM_RED, true);
			SetPlayerTeam(id, TEAM_RED);
			set_user_info(id, "topcolor", RED_COLOR_STR);
			set_user_info(id, "bottomcolor", RED_COLOR_STR);
		}
	}

	if (is_user_alive(id)) {
		hl_user_kill(id);
	}

	SetPlayerClass(id, FB_CLASS_NONE);

	menu_destroy(menu);

	DisplayClassMenu(id);

	return PLUGIN_HANDLED;
}

public CmdClassMenu(id) {
	if (GetPlayerTeam(id) == TEAM_NONE) {
		DisplayTeamMenu(id);
		return PLUGIN_CONTINUE;
	} 

	DisplayClassMenu(id);
	
	return PLUGIN_CONTINUE;
}

public DisplayClassMenu(id) {
	if (!GetPlayerTeam(id))
		return;

	new menu = menu_create(fmt("%l", "FB_CLASSMENU"), "HandlerClassMenu");
	new cb = menu_makecallback("CallBackClassMenu"); 

	menu_additem(menu, fmt("%L", id, "FB_CLASS_SCOUT"), fmt("%d", FB_CLASS_SCOUT));
	menu_additem(menu, fmt("%L", id, "FB_CLASS_MEDIC"), fmt("%d", FB_CLASS_MEDIC));
	menu_additem(menu, fmt("%L", id, "FB_CLASS_SOLDIER"), fmt("%d", FB_CLASS_SOLDIER));
	menu_additem(menu, fmt("%L", id, "FB_CLASS_CIVILIAN"), fmt("%d", FB_CLASS_CIVILIAN), .callback = cb);
	menu_setprop(menu, MPROP_NOCOLORS, true);

	menu_display(id, menu);
}

public CallBackClassMenu(id, menu, item) {
	new info[3];
	menu_item_getinfo(menu, item, _, info, charsmax(info));

	new team = GetPlayerTeam(id);
	new class = str_to_num(info);

	// to do: update class menu when the class is now available
	if (class == FB_CLASS_CIVILIAN) {
		// too many players in this class
		if (GetPlayersNumByClass(team, FB_CLASS_CIVILIAN) > 0) {
			return ITEM_DISABLED;
		}
	}
	return ITEM_IGNORE;
}

// faltan los chequeso den disconect, resetear todo cuando se vaya, o cuandos emande restart, el primeo  sea
public HandlerClassMenu(id, menu, item) {
	if (item == MENU_EXIT) {
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	new info[3];
	menu_item_getinfo(menu, item, _, info, charsmax(info));

	new team = GetPlayerTeam(id);
	new class = str_to_num(info);

	if (class == FB_CLASS_CIVILIAN) {
		// too many players in this class, remove menu and display again...
		if (GetPlayersNumByClass(team, FB_CLASS_CIVILIAN) > 0) {
			menu_destroy(menu);
			DisplayClassMenu(id);
			return PLUGIN_HANDLED;
		}
	}

	SetPlayerClass(id, class);

	if (hl_get_user_spectator(id)) {
		hl_set_user_spectator(id, false);
	} else if (is_user_alive(id)) {
		hl_user_kill(id);
	}

	menu_destroy(menu);

	return PLUGIN_HANDLED;
}
/* ====================
*/

/* Get and set functions
*/
public GetPlayerTeam(id) {
	return pev(id, pev_iuser4);
}

public SetPlayerTeam(id, teamid) {
	set_pev(id, pev_iuser4, teamid);
}

public SetPlayerClass(id, class) {
	set_pev(id, pev_playerclass, class);
}

public GetPlayerClass(id) {
	return pev(id, pev_playerclass);
}

public AddPointsToScore(team, value) {
	g_TeamScore[team - 1] += value;
}

public GetTeamScore(team) {
	return g_TeamScore[team - 1];
}

public GetBallOwner() {
	return pev(g_EntBall, pev_aiment);
}

public SetBallLastOwner(id) {
	set_pev(g_EntBall, pev_iuser1, id);
}

stock GetBallLastOwner() {
	return pev(g_EntBall, pev_iuser1);
}

// set to true to make the wall solid, false otherwise
public SetDividingWall(bool:value) {
	ExecuteHam(Ham_Use, g_EntDividingWall, 0, 0, value ? USE_ON : USE_OFF, 0.0);
}

/* ===================
*/

/* Player Classes
*/

public SetClassAtribbutes(id) {
	switch (GetPlayerClass(id)) {
		case FB_CLASS_SCOUT: SetScout(id);
		case FB_CLASS_MEDIC: SetMedic(id);
		case FB_CLASS_SOLDIER: SetSoldier(id);
		case FB_CLASS_CIVILIAN: SetCivilian(id);
	}
}

public SetSoldier(id) {
	SetPlayerClass(id, FB_CLASS_SOLDIER);
	hl_set_player_model(id, MDL_SOLDIER);

	hl_set_user_health(id, 100);
	hl_set_user_armor(id, 100);
	set_user_maxspeed(id, 230.0);

	hl_strip_user_weapons(id);

	give_item(id, "weapon_crowbar");
	give_item(id, "weapon_glock");
	give_item(id, "weapon_shotgun");
	give_item(id, "weapon_rpg");

	hl_set_user_bpammo(id, HLW_RPG, 10);
	hl_set_user_bpammo(id, HLW_GLOCK, 96);
	hl_set_user_bpammo(id, HLW_SHOTGUN, 64);
}

public SetMedic(id) {
	SetPlayerClass(id, FB_CLASS_MEDIC);
	hl_set_player_model(id, MDL_MEDIC);

	hl_set_user_health(id, 90);
	hl_set_user_armor(id, 100);
	set_user_maxspeed(id, 270.0);

	hl_strip_user_weapons(id);

	give_item(id, "weapon_crowbar");
	give_item(id, "weapon_glock");
	give_item(id, "weapon_shotgun");
	give_item(id, "weapon_mp5");

	hl_set_user_bpammo(id, HLW_PYTHON, 24);
	hl_set_user_bpammo(id, HLW_GLOCK, 150);
	hl_set_user_bpammo(id, HLW_SHOTGUN, 64);
}

public SetScout(id) {
	SetPlayerClass(id, FB_CLASS_SCOUT);
	hl_set_player_model(id, MDL_SCOUT);

	hl_set_user_health(id, 75);
	hl_set_user_armor(id, 50);
	set_user_maxspeed(id, 300.0);

	hl_strip_user_weapons(id);

	give_item(id, "weapon_crowbar");
	give_item(id, "weapon_glock");
	give_item(id, "weapon_357");
	give_item(id, "weapon_handgrenade");

	hl_set_user_bpammo(id, HLW_PYTHON, 24);
	hl_set_user_bpammo(id, HLW_GLOCK, 96);
}

public SetCivilian(id) {
	SetPlayerClass(id, FB_CLASS_CIVILIAN);
	hl_set_player_model(id, MDL_CIVILIAN);

	set_user_godmode(id, true);
	hl_set_user_health(id, 50);
	hl_set_user_armor(id, 0);
	set_user_maxspeed(id, 300.0);

	hl_strip_user_weapons(id);
	
	give_item(id, "weapon_crowbar");
	hl_set_user_longjump(id, true);

	set_pev(id, pev_viewmodel2, MDL_V_UMBRELLA);
	set_pev(id, pev_weaponmodel2, MDL_P_UMBRELLA);

	// set glow
	set_user_rendering(id, kRenderFxGlowShell, 200, 45, 255, kRenderNormal, 30);
}

/* ===================
*/

/*General Stocks
*/

stock RemoveExtension(const input[], output[], length, const ext[]) {
	copy(output, length, input);

	new idx = strlen(input) - strlen(ext);
	if (idx < 0) return 0;

	return replace(output[idx], length, ext, "");
}

stock PlaySound(id, const sound[], removeExt = true) {
	new snd[128];
	// Remove .wav file extension (console starts to print "missing sound file _period.wav" for every sound)
	// Don't remove  in case the string already has no extension
	if (removeExt) {
		RemoveExtension(sound, snd, charsmax(snd), ".wav");
	}
	client_cmd(id, "spk %s", snd);
}

stock SpeakSnd(id, const sound[], removeExt = true) {
	new snd[128];
	// Remove .wav file extension (console starts to print "missing sound file _period.wav" for every sound)
	// Don't remove  in case the string already has no extension
	if (removeExt) {
		RemoveExtension(sound, snd, charsmax(snd), ".wav");
	}
	client_cmd(id, "speak %s", snd);
}

stock TeleportToSpawn(id, spawn) {
	new Float:origin[3];
	new Float:angle[3];

	if (!pev_valid(id))
		return;

	// get origin and angle of spawn
	pev(spawn, pev_origin, origin);
	pev(spawn, pev_angles, angle);

	// teleport it
	entity_set_origin(id, origin);
	set_pev(id, pev_angles, angle);
	set_pev(id, pev_fixangle, 1);
}

stock GetPlayersNumByClass(teamid, classid) {
	new players[32], numPlayers;
	get_players_ex(players, numPlayers, GetPlayers_ExcludeHLTV);

	new plr, numClass;
	for (new i; i < numPlayers; i++) {
		plr = players[i];
		if (GetPlayerTeam(plr) == teamid && GetPlayerClass(plr) == classid) {
			numClass++;
		}
	}

	return numClass;
}

stock create_teleport_splash(ent) {
	new Float:origin[3];
	pev(ent, pev_origin, origin);

	message_begin_f(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_TELEPORT);
	write_coord_f(origin[0]);
	write_coord_f(origin[1]);
	write_coord_f(origin[2]);
	message_end();
}

stock CustomHudMsg(id, const playerMsg[] = "", const teamMsg[] = "", const nonTeamMsg[] = "") {
	new teamName[16];
	hl_get_user_team(id, teamName, charsmax(teamName));
	
	set_hudmessage(255, 255, 255, -1.0, 0.75, 2, 0.03, 5.0, 0.03, 0.5);

	if (!equal(playerMsg, ""))
		ShowSyncHudMsg(id, g_HudCtfMsgSync, "%L", LANG_PLAYER, playerMsg);

	new playersTeam[32], numTeam;
	get_players(playersTeam, numTeam, "ce", teamName);

	new player;
	if (!equal(teamMsg, "")) {
		for (new i; i < numTeam; i++) {
			player = playersTeam[i];
			if (player != id)
				ShowSyncHudMsg(player, g_HudCtfMsgSync, "%L", LANG_PLAYER, teamMsg);
		}
	}

	new players[32], num;
	get_players(players, num, "c");

	if (!equal(nonTeamMsg, "")) {
		for (new i; i < num; i++) {
			player = players[i];

			if (!array_search(player, playersTeam, numTeam))		
				ShowSyncHudMsg(player, g_HudCtfMsgSync, "%L", LANG_PLAYER, nonTeamMsg);
		}
	}
}

stock bool:array_search(value, array[], size) {
	new bool:match;
	for (new i; i < size; i++)
		if (array[i] == value)
			match = true; 
	return match;
}

// Change player team by teamid
stock ChangePlayerTeam(id, teamId, kill = false) {
	static gameTeamMaster, gamePlayerTeam, spawnFlags;

	if (!gameTeamMaster) {
		gameTeamMaster = create_entity("game_team_master");
		set_pev(gameTeamMaster, pev_targetname, "changeteam");
	}

	if (!gamePlayerTeam) {
		gamePlayerTeam = create_entity("game_player_team");
		DispatchKeyValue(gamePlayerTeam, "target", "changeteam");
	}

	if (kill)
		spawnFlags = spawnFlags | SF_PTEAM_KILL;

	set_pev(gamePlayerTeam, pev_spawnflags, spawnFlags);

	DispatchKeyValue(gameTeamMaster, "teamindex", fmt("%i", teamId - 1));

	ExecuteHamB(Ham_Use, gamePlayerTeam, id, 0, USE_ON, 0.0);
}

// i'm wondering if i'm not removing well the entities, eventually i will reach the max entities and the server will crash...
stock WeaponBox_RemoveWeapons(const pWeaponBox) { 
	new pWeapon, i; 

	// destroy the weapons 
	for (i = 0; i < 6; i++)  { 
		pWeapon = get_ent_data_entity(pWeaponBox, "CWeaponBox", "m_rgpPlayerItems", i);

		if (pev_valid(pWeapon)) { 
			set_pev(pWeapon, pev_flags, FL_KILLME);
			set_ent_data_entity(pWeaponBox, "CWeaponBox", "m_rgpPlayerItems", get_ent_data_entity(pWeapon, "CBasePlayerItem", "m_pNext"), i);
		} 
	} 
}

// Cache this in plugin_precache() or plugin_init() because the team code doesn't deal with changing this in the middle of a game
stock GetTeamListModels(output[][], size, &numTeams = 0) {
	new teamlist[512];
	get_cvar_string("mp_teamlist", teamlist, charsmax(teamlist));

	new nLen, teamname[HL_TEAMNAME_LENGTH];
	while (nLen < strlen(teamlist) && numTeams < HL_MAX_TEAMS)
	{
		strtok(teamlist[nLen], teamname, charsmax(teamname), "", 0, ';');
		nLen += strlen(teamname) + 1;
		if (GetTeamIndex(teamname, output, numTeams) < 0)
		{
			copy(output[numTeams], size, teamname);
			numTeams++;
		}
	}

	if (numTeams < 2)
		numTeams = 0;
}

stock GetTeamIndex(const teamname[], teamlist[][], numTeams){
	for (new i = 0; i < numTeams; i++)
		if (equali(teamlist[i], teamname))
			return i;
	return -1;
}

stock ColorTeamTrail(id) {
	if (GetPlayerTeam(id) == TEAM_BLUE) {
		te_create_following_beam(id, g_SprBeam, 10, 10, 0, 0, 255, 255, .reliable = false);
	} else if (GetPlayerTeam(id) == TEAM_RED) {
		te_create_following_beam(id, g_SprBeam, 10, 10, 255, 0, 0, 255, .reliable = false);
	}
}

stock kill_trail_msg(id) {
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_KILLBEAM);
	write_short(id);
	message_end();
}

stock DrawFlagIcon(id, bool:status, team) {
	static StatusIcon;

	if (!StatusIcon)
		StatusIcon = get_user_msgid("StatusIcon");

	new r, g, b, sprite[32];
	
	if (team == TEAM_RED) {
		r = 255; g = 60; b = 60; 
		copy(sprite, charsmax(sprite), "dmg_gas");
	} else if (team == TEAM_BLUE) {
		r = 60; g = 100; b = 255; 
		copy(sprite, charsmax(sprite), "dmg_gas");
	}
	message_begin(MSG_ONE, StatusIcon, .player = id);
	write_byte(status);
	write_string(sprite);
	write_byte(r);
	write_byte(g);
	write_byte(b);
	message_end();
}

stock hl_user_kill(id) {
	new deaths = hl_get_user_deaths(id);
	user_kill(id, true);
	hl_set_user_deaths(id, deaths);	
}

stock UpdateTeamNames(id = 0) {
	new blue[HL_MAX_TEAMNAME_LENGTH];
	new red[HL_MAX_TEAMNAME_LENGTH];

	// Get translated team name
	SetGlobalTransTarget(id);
	formatex(blue, charsmax(blue), "%l", "FB_TEAM_BLUE");
	formatex(red, charsmax(red), "%l", "FB_TEAM_RED");

	// Stylize it to uppercase
	strtoupper(blue);
	strtoupper(red);

	hl_set_user_teamnames(id, blue, red);
}

stock UpdateTeamScore(id = 0) {
	hl_set_user_teamscore(id, g_TeamNames[TEAM_BLUE - 1], GetTeamScore(TEAM_BLUE));
	hl_set_user_teamscore(id, g_TeamNames[TEAM_RED - 1], GetTeamScore(TEAM_RED));
}
