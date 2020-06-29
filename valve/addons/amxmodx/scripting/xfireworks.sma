// Based on:
// - Xmas Fireworks from Milashkasiya (Based on Fireworks++)
// - Fireworks++ from Twilight Suzuka.

// Mostly what I did was a rewrite from the ground because the old code
// wasn't suitable for making an API, because it was hard to read and mantain.

#include <amxmodx>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <hlstocks>
#include <msgstocks>

#define PLUGIN  "X-Fireworks"
#define VERSION "1.0"
#define AUTHOR  "rtxA"

#pragma semicolon 1

// --------------------------------- Models ---------------------------------

new const MDL_RPGAMMO[]         = "models/w_rpgammo.mdl";
new const MDL_RPGROCKET[]       = "models/rpgrocket.mdl";
new const MDL_RPGROCKET_T[]     = "models/w_rpgammot.mdl";

// --------------------------------- Sounds ---------------------------------

new const SND_WEAPONDROP1[]     = "items/weapondrop1.wav";
new const SND_ROCKET_LAUNCH[]   = "fireworks/rocket1.wav";

// --------------------------------- Sprites ---------------------------------

new const SPR_LASERBEAM[]   = "sprites/laserbeam.spr";
new const SPR_FLARE6[]      = "sprites/flare6.spr";
new const SPR_LGTNING[]     = "sprites/lgtning.spr";
new const SPR_EXPLODE1[]    = "sprites/explode1.spr";
new const SPR_STEAM1[]      = "sprites/steam1.spr";
new const SPR_FLARES[][]    = {
    "sprites/fireworks/bflare.spr",
    "sprites/fireworks/rflare.spr",
    "sprites/fireworks/gflare.spr",
    "sprites/fireworks/tflare.spr",
    "sprites/fireworks/oflare.spr",
    "sprites/fireworks/pflare.spr",
    "sprites/fireworks/yflare.spr"
};

// ------------------------------------------------------------------

// entities classnames and size
new const CLASSNAME_SHOOTER[] = "fireworks_shooter";
new const CLASSNAME_ROCKET[] = "fireworks_rocket";
new const Float:ROCKET_MINS[3] = { -4.0, -4.0, -1.0 };
new const Float:ROCKET_MAXS[3] = { 4.0, 4.0, 12.0 };

// global sprites indexes
new g_sLaserBeam;
new g_sFlare;
new g_sLgtning;
new g_sExplode;
new g_sSteam;
new g_sFlares[sizeof(SPR_FLARES)];

// cvars
new g_pCvarEnable;
new g_pCvarShots;
new g_pCvarLights;

// used in shooter entities
new Array:g_ShootersPos;
#define Pev_Shots pev_iuser1

// used in rocket entities
new g_RocketsNum;
#define Pev_ExplodeTime     pev_fuser1 // used too in shooter for initialization
#define Pev_NextVelChange   pev_fuser2

public plugin_precache() {
    precache_model(MDL_RPGAMMO);
    precache_model(MDL_RPGROCKET);
    precache_model(MDL_RPGROCKET_T);

    precache_sound(SND_WEAPONDROP1);
    precache_sound(SND_ROCKET_LAUNCH);

    g_sLaserBeam= precache_model(SPR_LASERBEAM);
    g_sFlare = precache_model(SPR_FLARE6);
    g_sLgtning = precache_model(SPR_LGTNING);
    g_sExplode = precache_model(SPR_EXPLODE1);
    g_sSteam = precache_model(SPR_STEAM1);

    for (new i; i < sizeof(SPR_FLARES); i++)
        g_sFlares[i] = precache_model(SPR_FLARES[i]);
}

public plugin_natives() {
    g_ShootersPos = ArrayCreate(3);
    register_native("fireworks_add_shooter", "native_add_shooter");
    register_native("fireworks_start_shooters", "native_start_shooters");
    //register_native("fireworks_clear_shooters", "native_clear_shooters");
}

public native_add_shooter(plugin_id, argc) {
    if (argc < 1)
        return false;

    new Float:origin[3];
    get_array_f(1, origin, sizeof(origin));

    // todo: let the native select explode time
    //new Float:explodeTime = get_param_f(2);

    ArrayPushArray(g_ShootersPos, origin);

    return true;
}

public native_start_shooters(plugin_id, argc) {
    CreateAllShooters();
}

public plugin_init() {
    register_plugin(PLUGIN, VERSION, AUTHOR);

    register_think(CLASSNAME_SHOOTER, "OnShooterThink");
    register_think(CLASSNAME_ROCKET, "OnRocketThink");
    register_touch("*", CLASSNAME_ROCKET, "OnRocketTouch");

    g_pCvarEnable = register_cvar("xfireworks_enable", "1");
    g_pCvarShots = register_cvar("xfireworks_shots", "10"); // Especifica cuantos cohetes por disparador seran creados
    g_pCvarLights = register_cvar("xfireworks_lights", "1"); // # Habilita los efectos de luces.    
}

public plugin_end() {
    ArrayDestroy(g_ShootersPos);
}

CreateAllShooters() {
    if (!get_pcvar_bool(g_pCvarEnable))
        return;

    new shots = get_pcvar_num(g_pCvarShots);

    g_RocketsNum = shots * ArraySize(g_ShootersPos);
    
    new Float:origin[3];
    for (new i; i < ArraySize(g_ShootersPos); i++) {
        ArrayGetArray(g_ShootersPos, i, origin);
        CreateShooter(origin, shots);
    }	
}

CreateShooter(const Float:origin[3], shots) {
    new entity = create_entity("info_target");

    if (!entity)
        return;
    
    set_pev(entity, pev_classname, CLASSNAME_SHOOTER);
    entity_set_model(entity, MDL_RPGAMMO);

    set_pev(entity, pev_movetype, MOVETYPE_TOSS);
    set_pev(entity, Pev_Shots, shots);
    
    entity_set_origin(entity, origin);
    DispatchSpawn(entity);
    
    emit_sound(entity, CHAN_WEAPON, SND_WEAPONDROP1, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    set_pev(entity, pev_nextthink, get_gametime() + random_float(0.1, 1.5));
}

// launch fireworks one per one
public OnShooterThink(shooter) {
    new Float:origin[3];
    pev(shooter, pev_origin, origin);

    new shots = pev(shooter, Pev_Shots);

    if (shots > 0) {
        CreateRocket(shooter, origin);
        shots--;
    }

    if (!shots) {
        remove_entity(shooter);
    } else {
        set_pev(shooter, Pev_Shots, shots);
        set_pev(shooter, pev_nextthink, get_gametime() + random_float(0.1, 1.5));
    }

}

CreateRocket(shooter, Float:origin[3]) {
    new entity = create_entity("info_target");
    
    if (!entity)
        return;

    set_pev(entity, pev_classname, CLASSNAME_ROCKET);

    entity_set_model(entity, MDL_RPGROCKET);
    entity_set_size(entity, ROCKET_MINS, ROCKET_MAXS);
    
    set_pev(entity, pev_solid, SOLID_SLIDEBOX);
    set_pev(entity, pev_movetype, MOVETYPE_TOSS);
    set_pev(entity, Pev_ExplodeTime, get_gametime() + 1.0); // hardcoded explode time, we need to remov ethis...
    set_pev(entity, pev_owner, shooter);
    set_pev(entity, pev_angles, Float:{ 90.0, 0.0, 0.0 });
    
    origin[2] += 5.0;
    entity_set_origin(entity, origin);
    DispatchSpawn(entity);
    
    // beamfollow effect with random color
    te_create_following_beam(entity, g_sLaserBeam, 60, 4, random(256), random(256), random(256), random_num(200, 255));
    
    emit_sound(entity, CHAN_WEAPON, SND_ROCKET_LAUNCH, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    set_pev(entity, pev_nextthink, get_gametime() + 0.1);
}

public OnRocketThink(entity) {    
    new Float:origin[3];
    pev(entity, pev_origin, origin);

    if (pev_float(entity, Pev_ExplodeTime) <= get_gametime()) {
        ExplodeRocket(entity);
    } else {
        if (pev(entity, Pev_NextVelChange) <= get_gametime()) {
            new Float:velocity[3];
            velocity[0] = random_float(-100.0, 100.0);
            velocity[1] = random_float(-100.0, 100.0);
            velocity[2] = random_float( 800.0, 1800.0);
            set_pev(entity, pev_velocity, velocity);            
            set_pev(entity, Pev_NextVelChange, get_gametime() + random_float(0.1, 1.5));
        }
        set_pev(entity, pev_nextthink, get_gametime() + 0.1);
    }
}

// generally will touch the sky, a roof or whatever
public OnRocketTouch(touched, toucher) {
    ExplodeRocket(toucher);
}

ExplodeRocket(rocket) {
    new output[16];
    if (get_pcvar_num(g_pCvarLights)) {		
        if (--g_RocketsNum > 0)
            formatex(output, charsmax(output), "%s", "mnopqrst");
        else
            formatex(output, charsmax(output), "#OFF");

        set_lights(output);
    }
        
    new Float:origin[3];
    pev(rocket, pev_origin, origin);

    //////////////////////////////////////////////
    message_begin_f(MSG_PVS, SVC_TEMPENTITY, origin);
    write_byte(TE_BEAMDISK);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2]);
    write_coord(0);
    write_coord(0);
    write_coord(100);
    write_short(random(2) ? g_sFlare : g_sLgtning);
    write_byte(100);
    write_byte(0);
    write_byte(35); // life
    write_byte(0); // line width
    write_byte(150); // noise
    write_byte(random(256));
    write_byte(random(256));
    write_byte(random(256));
    write_byte(255);
    write_byte(5);
    message_end();

    //////////////////////////////////////////////
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_SPRITETRAIL);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2] - 20);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2] + 20);
    write_short(g_sFlares[random(sizeof g_sFlares)]);
    write_byte(random_num(50, 100)); // count
    write_byte(10); // life in 0.1's
    write_byte(10); // scale in 0.1's
    write_byte(random_num(40, 100)); // velocity along vector in 10's
    write_byte(60); // randomness of velocity in 10's
    message_end();
    
    ////////////////////////////////////////////// 
    message_begin_f(MSG_PAS, SVC_TEMPENTITY, origin);
    write_byte(TE_EXPLOSION);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2]);
    write_short(g_sExplode); 
    write_byte(random_num(10, 20)); // byte (scale in 0.1's) 188 
    write_byte(10); // byte (framerate) 
    write_byte(0); // byte flags 
    message_end();
    
    //////////////////////////////////////////////	
    message_begin_f(MSG_PAS, SVC_TEMPENTITY, origin);
    write_byte(TE_TAREXPLOSION);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2] - 40.0);
    message_end();
    
    ////////////////////////////////////////////// 
    message_begin_f(MSG_PVS, SVC_TEMPENTITY, origin);
    write_byte(TE_SMOKE);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2]);
    write_short(g_sSteam);
    write_byte(random_num(20, 40));
    write_byte(12);
    message_end();
    
    //////////////////////////////////////////////
    message_begin_f(MSG_PVS, SVC_TEMPENTITY, origin);
    write_byte(TE_DLIGHT);
    write_coord_f(origin[0]);
    write_coord_f(origin[1]);
    write_coord_f(origin[2]);
    write_byte(random_num(20, 50));
    write_byte(random(256));
    write_byte(random(256));
    write_byte(random(256));
    write_byte(100);
    write_byte(15);
    message_end();

    remove_entity(rocket);
}

// Use this only with float fields
stock Float:pev_float(_index, _value) {
    new Float:value;
    pev(_index, _value, value);
    return value;
}