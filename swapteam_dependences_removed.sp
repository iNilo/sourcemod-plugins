#include <sourcemod>
#include <cstrike>
//#include <cnf_core>

// @TODO: move COMMAND_FILTER_NONE define to cnf_core
// @TODO: better finishing messages that explain what status it got switched to instead of general "toggle"

#pragma newdecls required
#pragma semicolon 1

#define COMMAND_FILTER_NONE 0

bool g_bSwapAfterRound[MAXPLAYERS + 1];
bool g_bSwapOnDeath[MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	RegAdminCmd("sm_swapteam", Command_Swapteam, ADMFLAG_SLAY);
	RegAdminCmd("sm_swapteam_d", Command_Swapteam_Round_Prestart, ADMFLAG_SLAY);
	RegAdminCmd("sm_swapteam_death", Command_Swapteam_Death, ADMFLAG_SLAY);
	RegAdminCmd("sm_team", Command_Team, ADMFLAG_SLAY);
	
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_PlayerTeam);
}

public Action Command_Swapteam(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_swapteam <name|#userid|@all|@t|@ct>");
		return Plugin_Handled;
	}
	
	char target[32];
	GetCmdArg(1, target, sizeof(target));
	
	char target_name[32];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
				target, 
				client, 
				target_list, 
				MAXPLAYERS, 
				COMMAND_FILTER_NONE, 
				target_name, 
				sizeof(target_name), 
				tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		if (GetClientTeam(target_list[i]) < CS_TEAM_T)
		{
			continue;
		}
		
		SwitchTeam(target_list[i]);
		
		if (IsPlayerAlive(target_list[i]))
		{
			CS_RespawnPlayer(target_list[i]);
		}
	}
	
	if (tn_is_ml)
	{
		ShowActivity2(client, "[SWAPTEAM] ", "Swapped %t to the opposite team!", target_name);
	}
	else
	{
		ShowActivity2(client, "[SWAPTEAM] ", "Swapped %s to the opposite team!", target_name);
	}
	
	return Plugin_Handled;
}

public Action Command_Swapteam_Round_Prestart(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_swapteam_d <name|#userid|@all|@t|@ct>");
		return Plugin_Handled;
	}
	
	char target[32];
	GetCmdArg(1, target, sizeof(target));
	
	char target_name[32];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
				target, 
				client, 
				target_list, 
				MAXPLAYERS, 
				0, 
				target_name, 
				sizeof(target_name), 
				tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		g_bSwapAfterRound[target_list[i]] = !g_bSwapAfterRound[target_list[i]];
	}
	
	if (tn_is_ml)
	{
		ShowActivity2(client, "[RESPAWN] ", "%t will be switched to the opposite team on round end!", target_name);
	}
	else
	{
		ShowActivity2(client, "[RESPAWN] ", "%s will be switched to the opposite team on round end!", target_name);
	}
	
	return Plugin_Handled;
}

public Action Command_Swapteam_Death(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_swapteam_death <name|#userid|@all|@t|@ct>");
		return Plugin_Handled;
	}
	
	char target[32];
	GetCmdArg(1, target, sizeof(target));
	
	char target_name[32];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
				target, 
				client, 
				target_list, 
				MAXPLAYERS, 
				COMMAND_FILTER_ALIVE, 
				target_name, 
				sizeof(target_name), 
				tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		g_bSwapOnDeath[target_list[i]] = !g_bSwapOnDeath[target_list[i]];
	}
	
	if (tn_is_ml)
	{
		ShowActivity2(client, "[SWAPTEAM] ", "Toggled swapteam on death for %t!", target_name);
	}
	else
	{
		ShowActivity2(client, "[SWAPTEAM] ", "Toggled swapteam on death for %s!", target_name);
	}
	
	return Plugin_Handled;
}

public Action Command_Team(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "Usage: sm_team <name|#userid|@all|@t|@ct> <1=spectator|2=prisoner|3=guard>");
		return Plugin_Handled;
	}
	
	char target[32];
	GetCmdArg(2, target, sizeof(target));
	
	int iTeam = StringToInt(target);
	
	if (iTeam <= CS_TEAM_NONE || iTeam > CS_TEAM_CT)
	{
		ReplyToCommand(client, "Do not try to add people to an invalid team!");
		return Plugin_Handled;
	}
	
	GetCmdArg(1, target, sizeof(target));
	
	char target_name[32];
	int target_list[MAXPLAYERS];
	int target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
				target, 
				client, 
				target_list, 
				MAXPLAYERS, 
				COMMAND_FILTER_ALIVE, 
				target_name, 
				sizeof(target_name), 
				tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	{
		SwitchTeam(target_list[i], iTeam);
	}
	
	if (tn_is_ml)
	{
		ShowActivity2(client, "[SWAPTEAM] ", "Changed team of %t!", target_name);
	}
	else
	{
		ShowActivity2(client, "[SWAPTEAM] ", "Changed team of %s!", target_name);
	}
	
	return Plugin_Handled;
}

void SwitchTeam(int client, int iTargetTeam = 0)
{
	if (!iTargetTeam)
	{
		iTargetTeam = GetClientTeam(client) == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	}
	
	CS_SwitchTeam(client, iTargetTeam);
}

void ResetTeamswitch(int client)
{
	g_bSwapAfterRound[client] = false;
	g_bSwapOnDeath[client] = false;
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !g_bSwapAfterRound[i])
		{
			continue;
		}
		
		int iTeam = GetClientTeam(i);
		int iTargetTeam = iTeam == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
		
		CS_SwitchTeam(i, iTargetTeam);
		
		g_bSwapAfterRound[i] = false;
	}
	
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!g_bSwapOnDeath[client])
	{
		return Plugin_Continue;
	}
	
	int iTeam = GetClientTeam(client);
	int iTargetTeam = iTeam == CS_TEAM_T ? CS_TEAM_CT : CS_TEAM_T;
	
	CS_SwitchTeam(client, iTargetTeam);
	
	g_bSwapOnDeath[client] = false;
	
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ResetTeamswitch(client);
} 
