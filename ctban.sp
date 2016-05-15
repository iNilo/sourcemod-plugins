#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <cnf_core>
#include <timedpunishment>
#include <teambalance>
#include <ctban>

#pragma semicolon 1
#pragma newdecls required

bool g_bIsCTBanned[MAXPLAYERS + 1];

public void OnPluginStart()
{
	//TimedPunishment_RegisterPunishment(GetMyHandle(), "sm_ctban", "sm_unctban", "CT ban", ADMFLAG_KICK, COUNTDOWN_ALIVE, false, true, "CTBan_OnStart", "CTBan_OnStop", "CTBan_OnJoin", "CTBan_OnLeave");
    TimedPunishment_RegisterPunishment("sm_ctban", "sm_unctban", "CT ban", ADMFLAG_KICK, COUNTDOWN_ALIVE, false, true, "CTBan_OnStart", "CTBan_OnStop", "CTBan_OnJoin", "CTBan_OnLeave");

	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
}

public void Core_OnClientPutInServer(int client)
{
	g_bIsCTBanned[client] = false;
}

public void CTBan_OnStart(int client)
{
	if (GetClientTeam(client) == CS_TEAM_CT)
	{
		ForcePlayerSuicide(client);
		CS_SwitchTeam(client, CS_TEAM_T);
	}
	
	g_bIsCTBanned[client] = true;
}

public void CTBan_OnStop(int client)
{
	g_bIsCTBanned[client] = false;
}

public void CTBan_OnJoin(int client)
{
	if (GetClientTeam(client) == CS_TEAM_CT)
	{
		ForcePlayerSuicide(client);
		CS_SwitchTeam(client, CS_TEAM_T);
	}
	
	g_bIsCTBanned[client] = true;
}

public void CTBan_OnLeave(int client)
{
	g_bIsCTBanned[client] = false;
}

public Action Event_PlayerTeam(Event event, char[] name, bool dontBroadcast)
{
	int iUserId = event.GetInt("userid");
	int iClient = GetClientOfUserId(iUserId);
	int iTeam = event.GetInt("team");

	if (iTeam != CS_TEAM_CT || !g_bIsCTBanned[iClient])
	{
		return Plugin_Continue;
	}

	dontBroadcast = true;
	CreateTimer(0.0, Timer_SwitchTeam, iUserId);

	return Plugin_Stop;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("IsCTBanned", Native_IsCTBanned);

	return APLRes_Success;
}

public int Native_IsCTBanned(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return view_as<int>(g_bIsCTBanned[client]);
}

public Action Teambalance_OnGuardJoinAttempt(int client)
{
	if (g_bIsCTBanned[client])
	{
		PrintHintText(client, "You are currently ctbanned and thus can't join CT");
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_SwitchTeam(Handle timer, any iUserId)
{
	int client = GetClientOfUserId(iUserId);
	
	if (client == 0 || GetClientTeam(client) != CS_TEAM_CT)
	{
		return Plugin_Stop;
	}
	
	CS_SwitchTeam(client, CS_TEAM_T);
	
	if (IsPlayerAlive(client))
	{
		// If the player was alive already, move him back to his team's spawn
		CS_RespawnPlayer(client);
	}
	
	return Plugin_Stop;
}