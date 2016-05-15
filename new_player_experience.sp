#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <cnf_core>
#include <teambalance>
#include <warden>


// @TODO: hook joining guard queue


/*
Show on:
- Attemting to join Guard
- Joining Guard
- Joining Prisoner
- Looking at Guard
- Looking at Warden
- Getting to LR / seeing LR
- Cell doors opening
- Becoming Warden
- On gun pickup
*/

#pragma newdecls required
#pragma semicolon 1

enum NewPlayerExperience
{
    b_newplayer = 0,
    b_sawguard,
    b_sawwarden,
    b_sawlastrequest,
    b_joinedprisoner,
    b_joinedguard,
	b_joinguardattempt
}

bool g_bNewPlayer[MAXPLAYERS+1][NewPlayerExperience];


public void OnPluginStart()
{
    //HookEvent("cs_prev_next_spectator", Event_Spectate);
    //HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_spawn", Event_PlayerSpawn);
}

public void Core_OnClientPutInServer(int client)
{
    g_bNewPlayer[client][b_newplayer] = false;
}

public void Core_OnFirstJoin(int client)
{
	g_bNewPlayer[client][b_newplayer] = true;
	g_bNewPlayer[client][b_sawguard] = false;
	g_bNewPlayer[client][b_sawwarden] = false;
	g_bNewPlayer[client][b_sawlastrequest] = false;
	g_bNewPlayer[client][b_joinedprisoner] = false;
	g_bNewPlayer[client][b_joinedguard] = false;
	g_bNewPlayer[client][b_joinguardattempt] = false;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!g_bNewPlayer[client][b_newplayer])
	{
		return Plugin_Continue;
	}

	int target = GetClientAimTarget(client);

	if (target > MaxClients || target <= 0 || GetClientTeam(target) != CS_TEAM_CT)
	{
		return Plugin_Continue;
	}

	if (warden_iswarden(target))
	{
		if (!g_bNewPlayer[client][b_sawwarden])
		{
			g_bNewPlayer[client][b_sawwarden] = true;
			PrintHintText(client, "The warden gives commands to T's. Follow them or you will be rebelling!");
		}

		return Plugin_Continue;
	}

	// Looking at a guard
	if (!g_bNewPlayer[client][b_sawguard])
	{
		g_bNewPlayer[client][b_sawguard] = true;
		PrintHintText(client, "The guard makes sure prisoners follow orders and keeps them from rebelling.");
	}

	return Plugin_Continue;
}

/*public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int iClient = GetClientOfUserId(event.GetInt("userid"));
	
	if (!g_bNewPlayer[iClient][b_newplayer])
	{
		return Plugin_Continue;
	}
	
    int iTeam = event.GetInt("team");
    int iOldTeam = event.GetInt("oldteam");
}*/

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (!g_bNewPlayer[iClient][b_newplayer])
	{
		return Plugin_Continue;
	}

	int iTeam = GetClientTeam(iClient);

	if (iTeam == CS_TEAM_T)
	{
		if (!g_bNewPlayer[iClient][b_joinedprisoner])
		{
			g_bNewPlayer[iClient][b_joinedprisoner] = true;
			PrintHintText(iClient, "You are a prisoner. Try and survive by any means possible but guards can't kill you if you follow orders.");
		}

		return Plugin_Continue;
	}

	if (iTeam == CS_TEAM_CT && !g_bNewPlayer[iClient][b_joinedguard])
	{
		g_bNewPlayer[iClient][b_joinedguard] = true;
		PrintHintText(iClient, "You are a guard. Enforce the warden's commands and defend him from rebellers!");
	}

	return Plugin_Continue;
}

public Action Teambalance_OnGuardJoinAttempt(int client)
{
	if (!g_bNewPlayer[client][b_newplayer] || g_bNewPlayer[client][b_joinguardattempt])
	{
		return Plugin_Continue;
	}
    
    g_bNewPlayer[client][b_joinguardattempt] = true;
    PrintHintText(client, "You must have a good microphone and know the rules to be a guard!");
	
	return Plugin_Continue;
}

public void Warden_OnBecomeWarden(int client)
{
    if (!g_bNewPlayer[client][b_newplayer] || g_bNewPlayer[client][b_becomewarden])
    {
        return Plugin_Continue;
    }
    
    g_bNewPlayer[client][b_becomewarden] = true;
    PrintHintText(client, "As warden you can command the prisoners to do things. Don't kill them if they do it.");
}