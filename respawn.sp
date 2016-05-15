#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <cnf_core>

#pragma newdecls required
#pragma semicolon 1

#define STAND_HEIGHT	64
#define DUCK_HEIGHT		46

float g_fDeathLocation[MAXPLAYERS+1][3];
float g_fDeathAngles[MAXPLAYERS+1][3];
int g_iDeathButtons[MAXPLAYERS+1];
int g_iFlags[MAXPLAYERS+1];
int g_iDucking[MAXPLAYERS+1];

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    RegAdminCmd("sm_respawn", Command_Respawn, ADMFLAG_SLAY);
    RegAdminCmd("sm_hrespawn", Command_HRespawn, ADMFLAG_SLAY);
    RegAdminCmd("sm_1up", Command_HRespawn, ADMFLAG_SLAY);
    RegAdminCmd("sm_aimrespawn", Command_AimRespawn, ADMFLAG_SLAY);
    
	HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("round_start", Event_RoundStart);

	AddCommandListener(Command_Kill, "kill");
	AddCommandListener(Command_Kill, "explode");
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnTakeDamage(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if (victim > 0 && victim <= MaxClients)
	{
		GetDeathLocationInfo(victim);
	}
}

void GetDeathLocationInfo(int client)
{
	GetClientAbsOrigin(client, g_fDeathLocation[client]);
	GetClientAbsAngles(client, g_fDeathAngles[client]);
	g_iDeathButtons[client] = GetClientButtons(client);
	g_iFlags[client] = GetEntityFlags(client);
	
	g_iDucking[client] = GetEntProp(client, Prop_Send, "m_bDucked");
}

void ResetLocation(int client)
{
    g_fDeathLocation[client] = NULL_VECTOR;
    g_fDeathAngles[client] = NULL_VECTOR;
    g_iDeathButtons[client] = 0;
	g_iFlags[client] = 0;
	
	g_iDucking[client] = 0;
}

stock void GetClientSightEnd(int client, float out[3])
{
	float fEyes[3];
	float fAngles[3];
	GetClientEyePosition(client, fEyes);
	GetClientEyeAngles(client, fAngles);
	TR_TraceRayFilter(fEyes, fAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceRay_NoPlayers);
	if(TR_DidHit())
		TR_GetEndPosition(out);
}

public bool TraceRay_NoPlayers(int entity, int mask, any data)
{
	if(0 < entity <= MaxClients)
		return false;
	return true;
}

public void RespawnPlayerOnDeathLocation(int client)
{
    CS_RespawnPlayer(client);

	// Why can you initialize with NULL_VECTOR but not check for it with ==? Anyways, look at optimizing this with bool?
    if (g_fDeathLocation[client][0] != 0.0 && g_fDeathLocation[client][1] != 0.0 && g_fDeathLocation[client][2] != 0.0)
    {
		if (g_iFlags[client] & FL_DUCKING)
		{
			SetEntProp(client, Prop_Send, "m_bDucked", 1);
		}
		
		SetEntProp(client, Prop_Data, "m_nButtons", g_iDeathButtons[client]);
		SetEntityFlags(client, g_iFlags[client]);
		
        TeleportEntity(client, g_fDeathLocation[client], g_fDeathAngles[client], NULL_VECTOR);
    }
}

public void RespawnPlayerOnLocation(int client, float fLocation[3])
{
    CS_RespawnPlayer(client);
    TeleportEntity(client, fLocation, NULL_VECTOR, NULL_VECTOR);
}

/************************************* COMMANDS ************************************/
public Action Command_Kill(int client, const char[] command, int argc)
{
	if (!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	GetDeathLocationInfo(client);
	
	return Plugin_Continue;
}

public Action Command_Respawn(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_respawn <name|#userid|@all|@t|@ct>");
        return Plugin_Handled;
    }
    
    char target[32];
    GetCmdArg(1, target, sizeof(target));
    
    char target_name[32];
    int target_list[MAXPLAYERS];
    int target_count;
    bool tn_is_ml;

    if ((target_count = Core_ProcessTargetString(
                    target,
                    client,
                    target_list,
                    MAXPLAYERS,
                    COMMAND_FILTER_DEAD,
                    target_name,
                    sizeof(target_name),
                    tn_is_ml)) <= 0)
    {
        ReplyToTargetError(client, target_count);
        return Plugin_Handled;
    }
    
    for (int i = 0; i < target_count; i++)
    {
        //if (GetClientTeam(target_list[i]) >= CS_TEAM_T)
        //{
            CS_RespawnPlayer(target_list[i]);
        //}
    }
    
    if (tn_is_ml)
	{
		Core_ShowActivity2(client, "[RESPAWN] ", "Respawned %t at spawn!", target_name);
	}
	else
	{
		Core_ShowActivity2(client, "[RESPAWN] ", "Respawned %s at spawn!", target_name);
	}
    
    return Plugin_Handled;
}

public Action Command_HRespawn(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_hrespawn <name|#userid|@all|@t|@ct>");
        return Plugin_Handled;
    }
    
    char target[32];
    GetCmdArg(1, target, sizeof(target));
    
    char target_name[32];
    int target_list[MAXPLAYERS];
    int target_count;
    bool tn_is_ml;

    if ((target_count = Core_ProcessTargetString(
                    target,
                    client,
                    target_list,
                    MAXPLAYERS,
                    COMMAND_FILTER_DEAD,
                    target_name,
                    sizeof(target_name),
                    tn_is_ml)) <= 0)
    {
        ReplyToTargetError(client, target_count);
        return Plugin_Handled;
    }
    
    for (int i = 0; i < target_count; i++)
    {
        /*if (GetClientTeam(i) < CS_TEAM_T)
        {
            continue;
        }*/
        
        RespawnPlayerOnDeathLocation(target_list[i]);
    }
    
    if (tn_is_ml)
	{
		Core_ShowActivity2(client, "[RESPAWN] ", "Respawned %t!", target_name);
	}
	else
	{
		Core_ShowActivity2(client, "[RESPAWN] ", "Respawned %s!", target_name);
	}
    
    return Plugin_Handled;
}

public Action Command_AimRespawn(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_aimrespawn <name|#userid|@all|@t|@ct>");
		return Plugin_Handled;
	}

	float fLocation[3];
	fLocation = NULL_VECTOR;
	GetClientSightEnd(client, fLocation);

	// Why can we initialize to NULL_VECTOR but not check if it is NULL_VECTOR?
	if (fLocation[0] == 0.0 && fLocation[1] == 0.0 && fLocation[2] == 0.0)
	{
		ReplyToCommand(client, "Please aim at a valid location when using sm_aimrespawn");
		return Plugin_Handled;
	}

	char target[32];
	GetCmdArg(1, target, sizeof(target));

	char target_name[32];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;

	if ((target_count = Core_ProcessTargetString(
					target,
					client,
					target_list,
					MAXPLAYERS,
					COMMAND_FILTER_DEAD,
					target_name,
					sizeof(target_name),
					tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		/*if (GetClientTeam(i) < CS_TEAM_T)
		{
			continue;
		}*/

		RespawnPlayerOnLocation(target_list[i], fLocation);
	}

	if (tn_is_ml)
	{
		Core_ShowActivity2(client, "[RESPAWN] ", "Respawned %t to aimlocation!", target_name);
	}
	else
	{
		Core_ShowActivity2(client, "[RESPAWN] ", "Respawned %s to aimlocation!", target_name);
	}

	return Plugin_Handled;
}

/****************************** Events *********************************/
public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    ResetLocation(client);
    
    return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
	{
		ResetLocation(i);
	}

    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client == 0 || g_fDeathLocation[client][0] != 0 || g_fDeathLocation[client][1] != 0 || g_fDeathLocation[client][2] != 0)
	{
		// We couldn't get the player's death location in a clean way (possibly a ForcePlayerSuicide), so try to get it in a hacky way
		return Plugin_Continue;
	}
	
	GetDeathLocationInfo(client);
	
	if (g_iDucking[client])
	{
		g_fDeathLocation[client][2] -= DUCK_HEIGHT;
		g_iDeathButtons[client] = g_iDeathButtons[client] & ~IN_DUCK;
		g_iDucking[client] = false;
		g_iFlags[client] &= FL_DUCKING;
	}
	else
	{
		g_fDeathLocation[client][2] -= STAND_HEIGHT;
	}
	
	return Plugin_Continue;
}