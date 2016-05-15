#include <sourcemod>
#include <cnf_core>
#include <timedpunishment>
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

#define MAXPUNISHMENTS 20

// @TODO: fire forward so punishments can reload themselves
// @TODO: possibility to set punishment till mapchange on 1 player?
// @TODO: add cookie fallback for when db is down?
// @TODO: offline punishments / removal
// @TODO: admin menu
// @TODO: further implementation of the new reason logic
// @TODO: let modules know the reason for the punishment (and how long left)
// @TODO: LogMessage


/****** Punishment Type *******/
/*enum PunishmentType
{
	i_id,
	String:s_command[20],
	String:s_name[32],
	Countdown:c_countdownType,
	i_adminflags,
	Function:fn_start,
	Function:fn_stop,
	Function:fn_join,
	Function:fn_leave
};*/

enum PunishmentTypeInt
{
	i_id,
	i_countdownType,
	i_adminflags
}

enum PunishmentTypeString
{
	s_startcommand,
	s_stopcommand,
	s_name,
	s_fnStart,
	s_fnStop,
	s_fnJoin,
	s_fnLeave
}

enum PunishmentTypeBool
{
	b_allowMultipleTargets,
	b_allowOtherServerPunishments
}

// @TODO: to be able to save these as functions, check https://github.com/SourceMod-Store/store/blob/Store-2.0/scripting/store-core.sp 's view_as<Store_MenuItemClickCallback>
/*enum PunishmentTypeFunction
{
	fn_start,
	fn_stop,
	fn_join,
	fn_leave
}*/

/******** Punishment ********/
enum PunishmentInt
{
	i_id,
	i_time,
	i_timeremaining,
	i_admin,
    i_timeStart
}

enum PunishmentBool
{
	b_wasMultiTarget,
	b_active,
}

enum PunishmentString
{
	s_reason
}

int g_iPunishmentType[MAXPUNISHMENTS][PunishmentTypeInt];
char g_sPunishmentType[MAXPUNISHMENTS][PunishmentTypeString][64];
Handle g_hPunishmentType[MAXPUNISHMENTS] = { INVALID_HANDLE, ... }; // @TODO: also make this an enum for consistency?
//PunishmentTypeCallback g_fnPunishmentType[MAXPUNISHMENTS][PunishmentTypeFunction];
bool g_bPunishmentType[MAXPUNISHMENTS][PunishmentTypeBool];

int g_iPunishment[MAXPLAYERS+1][MAXPUNISHMENTS][PunishmentInt];
bool g_bPunishment[MAXPLAYERS+1][MAXPUNISHMENTS][PunishmentBool];
char g_sPunishment[MAXPLAYERS+1][MAXPUNISHMENTS][PunishmentString][255];

//int g_pPunishment[MAXPUNISHMENTS][PunishmentType]; // might need changing

int g_iEnabledPunishmentCount;

Database g_hDatabase = null;
int g_iServer = -1;

public Plugin myinfo =
{
	name = "Timed punishment core",
	author = "Meitis",
	description = "This plugin handles all timed punishments and the expiring of punishments",
	version = "0.1",
	url = ""
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	g_hDatabase = Core_GetDatabase();
	g_iServer = Core_GetServerId();

	RegConsoleCmd("sm_punishments", Command_MyPunishments);
	RegAdminCmd("sm_checkpunishments", Command_CheckPunishments, ADMFLAG_SLAY);

	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	CreateTimer(60.0, Timer_CountDown, _, TIMER_REPEAT);
}

public void Core_OnConnectionEstablished()
{
	g_hDatabase = Core_GetDatabase();

	RegisterUnregisteredPunishments();
}

public void OnMapEnd()
{
	for (int iPunishmentType = 0; iPunishmentType < g_iEnabledPunishmentCount; iPunishmentType++)
	{		
		for (int client = 1; client <= MaxClients; client++)
		{
			if (g_bPunishment[client][iPunishmentType][b_active] && (g_iPunishmentType[iPunishmentType][i_countdownType] == COUNTDOWN_CURRENTMAP || g_bPunishment[client][iPunishmentType][b_wasMultiTarget]))
			{
				RemovePunishment(client, iPunishmentType);
			}
		}
	}
}

void RegisterUnregisteredPunishments()
{
	// @TODO: change to transaction?
	for (int iPunishmentType = 0; iPunishmentType < g_iEnabledPunishmentCount; iPunishmentType++)
	{
		if (g_iPunishmentType[iPunishmentType][i_id] != -1)
		{
			continue;
		}
		
		char sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "SELECT `id` FROM `punishment_types` WHERE `command` = '%s'", g_sPunishmentType[iPunishmentType][s_startcommand]);
	
		g_hDatabase.Query(SQL_Callback_FetchPunishmentType, sQuery, iPunishmentType, DBPrio_High);
	}
}

public int GetPunishmentType(int iPunishmentTypeId)
{
	for (int i = 0; i < g_iEnabledPunishmentCount; i++)
	{
		if (g_iPunishmentType[i][i_id] == iPunishmentTypeId)
		{
			return i;
		}
	}
	
	return -1;
}

public Action Timer_CountDown(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			// Player isn't ingame, check next one
			continue;
		}
		
		int iTeam = GetClientTeam(i);
		if (!(iTeam == CS_TEAM_T || iTeam == CS_TEAM_CT))
		{
			// Player isn't on an active team
			continue;
		}
		
		// @TODO: move countdown type check outside of giant if?
		
		for (int j = 0; j < g_iEnabledPunishmentCount; j++)
		{
			// @TODO: add check for afk
			if (!g_bPunishment[i][j][b_active] || g_bPunishment[i][j][b_wasMultiTarget] || g_iPunishment[i][j][i_time] == 0 || !(g_iPunishmentType[j][i_countdownType] == COUNTDOWN_ONLINE || (g_iPunishmentType[j][i_countdownType] == COUNTDOWN_ALIVE && Core_IsPlayerAlive(i))))
			{
				// This shouldn't be counted down
				continue;
			}

			////if (g_bPunishment[i][j][b_active] && g_iPunishment[i][j][i_timeremaining] > 0 && (g_iPunishmentType[j][i_countdownType] == COUNTDOWN_ONLINE || (g_iPunishmentType[j][i_countdownType] == COUNTDOWN_ALIVE && Core_IsPlayerAlive(i))))
			//if (g_bPunishment[i][j][b_active] && g_bPunishment[i][j][b_shouldBeSaved] && (g_iPunishmentType[j][i_countdownType] == COUNTDOWN_ONLINE || (g_iPunishmentType[j][i_countdownType] == COUNTDOWN_ALIVE && Core_IsPlayerAlive(i))))
			//{
			g_iPunishment[i][j][i_timeremaining]--;
			
			if (g_iPunishment[i][j][i_timeremaining] != 0)
			{
				// If the punishment hasn't finished yet, don't remove it
				continue;
			}
			
			// Time has expired
			RemovePunishment(i, j);
			
			if (!g_bPunishment[i][j][b_wasMultiTarget]) // @TODO: we already block multitarget before, why still do it here?
			{
				PrintToChatAll("[Punishments] The %s on %N has expired.", g_sPunishmentType[j][s_name], i);
			}
			//}
		}
	}

	return Plugin_Continue;
}

void RemovePunishment(int iClient, int iPunishmentType, int iAdmin = 0, char[] sReason = "Punishment expired")
{
	if (!g_bPunishment[iClient][b_active])
	{
		LogError("We were asked to remove an already removed punishment");
	}
	
	int iEscapedReasonLength = (strlen(sReason) * 2) + 1;
	char[] sEscapedReason = new char[iEscapedReasonLength];
	g_hDatabase.Escape(sReason, sEscapedReason, iEscapedReasonLength);
	
	Function fnStop = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnStop]);
	Call_StartFunction(g_hPunishmentType[iPunishmentType], fnStop);
	Call_PushCell(iClient);
	Call_Finish();
	
	if (!g_bPunishment[iClient][iPunishmentType][b_wasMultiTarget] && g_iPunishment[iClient][iPunishmentType][i_id] != -1)
	{
		// iPunishment is the primary key for the punishment, not the one in the plugin!
		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "UPDATE `punishments` SET `active` = 0 AND `time_remaining` = %d AND `removed_by` = %d AND `removal_reason` = '%s' WHERE `id` = %d", g_iPunishment[iClient][iPunishmentType][i_timeremaining], Core_GetClientId(iAdmin), sEscapedReason, g_iPunishment[iClient][iPunishmentType][i_id]);
		
		// send sql to the database!
		g_hDatabase.Query(SQL_Callback_Void, sQuery, _, DBPrio_High);
	}
	
	g_bPunishment[iClient][iPunishmentType][b_active] = false;
	g_iPunishment[iClient][iPunishmentType][i_id] = -1;
}

public void SavePunishments(int client)
{	
	bool bHasSaveablePunishments = false;
	Transaction tx = new Transaction();
	
	for (int iPunishmentType = 0; iPunishmentType < g_iEnabledPunishmentCount; iPunishmentType++)
	{
		if (!g_bPunishment[client][iPunishmentType][b_active] || g_bPunishment[client][iPunishmentType][b_wasMultiTarget] || g_iPunishmentType[iPunishmentType][i_countdownType] == COUNTDOWN_CURRENTMAP)
		{
			// This punishment doesn't need updating
			continue;
		}
		
		char sQuery[255];
		if (g_iPunishment[client][iPunishmentType][i_id] == -1)
		{
			// Is this punishment still in the process of being saved?
			// @TODO: check the start time to see if we should maybe still try inserting this anyways	
			continue;
		}
		
		FormatEx(sQuery, sizeof(sQuery), "UPDATE `punishments` SET `time_remaining` = %d WHERE `id` = %d", g_iPunishment[client][iPunishmentType][i_timeremaining], g_iPunishment[client][iPunishmentType][i_id]);
		tx.AddQuery(sQuery);
	}
	
	if (bHasSaveablePunishments)
	{
		g_hDatabase.Execute(tx);
	}
	else
	{
		delete tx;
	}
}

public void Core_OnClientPutInServer(int client)
{
    // Probably not necessary but let's make sure everything is cleaned up
    for (int i = 1; i < MAXPUNISHMENTS; i++)
    {
        g_bPunishment[client][i][b_active] = false;
    }
}

public void Core_OnClientPostAdminCheck(int client, int clientId)
{
	char sSteamid64[32];
	GetClientAuthId(client, AuthId_SteamID64, sSteamid64, sizeof(sSteamid64));

	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, `punishment_type_id`, `server_id`, `time`, `time_remaining`, `reason` FROM `punishments` WHERE `steamid64` = %s AND `active` = 1", sSteamid64);
	
	g_hDatabase.Query(SQL_Callback_GetPunishments, sQuery, GetClientUserId(client), DBPrio_High);
}

public Action Event_PlayerDisconnect(Handle event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	

	for (int iPunishmentType = 0; iPunishmentType < g_iEnabledPunishmentCount; iPunishmentType++)
	{
		if (g_bPunishment[client][iPunishmentType][b_active])
		{
			// Let the plugin know this person with active punishment is leaving
			Function fnLeave = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnLeave]);
			//Function fnLeave = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_leave]);
			Call_StartFunction(g_hPunishmentType[iPunishmentType], fnLeave);
			Call_PushCell(client);
			Call_Finish();
		}
	}
	
	// @TODO: Save the punishment information for player
	SavePunishments(client);
}

public void Core_OnServerConnected(int iServer)
{
	g_iServer = iServer;
}

public void SQL_Callback_FetchPunishmentType(Database db, DBResultSet results, const char[] sError, any iPunishmentType)
{
	if (db == null || strlen(sError) != 0)
	{
		// We had an error, log it
		LogError("Could not retrieve the id for punishment command %s: %s", g_sPunishmentType[iPunishmentType][s_startcommand], sError);
		return;
	}
	
	if (results.FetchRow())
	{
		// The punishment was in the database, so let's get it's id
		InitializePunishmentType(iPunishmentType, results.FetchInt(0));
		GetPunishmentsForPunishmentType(iPunishmentType);
	}
	else
	{
		// The punishment is new, add it to the database
		// Chances are we don't have a database connection but at least that'd be logged
		char sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `punishment_types` (`command`, `name`, `countdown_type_id`) VALUES('%s', '%s', %d)", g_sPunishmentType[iPunishmentType][s_startcommand], g_sPunishmentType[iPunishmentType][s_name], g_iPunishmentType[iPunishmentType][i_countdownType]); // maybe not necessary to save the countdown method?

		g_hDatabase.Query(SQL_Callback_InsertPunishmentType, sQuery, iPunishmentType, DBPrio_High);
	}

}

public void SQL_Callback_InsertPunishmentType(Database db, DBResultSet results, const char[] sError, any iPunishmentType)
{
	if (db == null || strlen(sError) != 0)
	{
		// We had an error, log it
		LogError("Could not insert the id for punishment command %s: %s", g_sPunishmentType[iPunishmentType][s_startcommand], sError);
		return;
	}
	
	// The punishment type has been added to the database, so let's get it's id
	InitializePunishmentType(iPunishmentType, results.InsertId);
}

public void SQL_Callback_GetPunishments(Database db, DBResultSet results, const char[] sError, any iUserid)
{
    if (db == null || strlen(sError) != 0)
	{
		// We could not get the punishments for one of the players
		LogError("Could not retrieve the punishments for one of the players: %s", sError);
		return;
	}
    
    int iClient = GetClientOfUserId(iUserid);
    
    if (iClient == 0)
    {
        return;
    }
    
    // The player is still ingame
    while (results.FetchRow())
    {
        // id, punishment_type_id, server_id, time, time_remaining, reason

        int iPunishmentTypeId = results.FetchInt(1);
        int iPunishmentType = GetPunishmentType(iPunishmentTypeId);

        if (iPunishmentType == -1)
        {
            // We don't have a plugin using this punishment type
            continue;
        }

        int iServerId = results.FetchInt(2);

        if (!g_bPunishmentType[iPunishmentType][b_allowOtherServerPunishments] && g_iServer != iServerId)
        {
            // This punishment isn't supposed to be applied on this server
            continue;
        }

        g_iPunishment[iClient][iPunishmentType][i_id] = results.FetchInt(0);
        g_iPunishment[iClient][iPunishmentType][i_time] = results.FetchInt(3);
        g_iPunishment[iClient][iPunishmentType][i_timeremaining] = results.FetchInt(4);

        results.FetchString(5, g_sPunishment[iClient][iPunishmentType][s_reason], sizeof(g_sPunishment[][][]));

        g_bPunishment[iClient][iPunishmentType][b_wasMultiTarget] = false;
        g_bPunishment[iClient][iPunishmentType][b_active] = true;

        // Let the plugin know someone with this punishment joined
        Function fnJoin = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnJoin]);
        //Function fnJoin = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_join]);
        Call_StartFunction(g_hPunishmentType[iPunishmentType], fnJoin);
        Call_PushCell(iClient);
        Call_Finish();
    }
}

public void SQL_Callback_InsertPunishment(Database db, DBResultSet results, const char[] sError, any data)
{
	DataPack datapack = view_as<DataPack>(data);
	datapack.Reset();
	int iUserId = datapack.ReadCell();
	int client = iUserId ? GetClientOfUserId(iUserId) : -1;
	int iPunishmentType = datapack.ReadCell();
	delete datapack;
	
	if (db == null || strlen(sError) != 0)
	{
		// We had an error, log it
		LogError("Could not retrieve the id for punishment command %s: %s", g_sPunishmentType[iPunishmentType][s_startcommand], sError);
		return;
	}
	
	if (client > 0)
	{
		if (g_iPunishment[client][iPunishmentType][i_id] != -1)
		{
			// @TODO: handle this situation better
			// Uhm, if we get here something bad happened and probably a punishment got saved and removed again before the callback fired
			LogError("%N did a booboo, punishment got saved and removed before callback fired.", client);
		}

		// The player is still ingame
		g_iPunishment[client][iPunishmentType][i_id] = results.InsertId;
	}
}

public void SQL_Callback_PunishmentsForPunishmentType(Database db, DBResultSet results, const char[] sError, any iPunishmentType)
{
	if (db == null || strlen(sError) != 0)
	{
		LogError("Could not retrieve the punishments for punishment type %s", g_sPunishmentType[iPunishmentType][s_startcommand]);
		return;
	}
	
	while (results.FetchRow())
	{
		//id, user_id, server_id, time, time_remaining, reason
		// @TODO: optimise gettings punishment type and user from their id's
		
		int iClient = Core_GetClientOfClientId(results.FetchInt(1));
		int iServer = results.FetchInt(2);
		
		if (!iClient || (!g_bPunishmentType[iPunishmentType][b_allowOtherServerPunishments] && g_iServer != iServer))
		{
			// If the client isn't on the server anymore or if these server's punishments shouldn't be active here, skip it
			continue;
		}
		
		g_iPunishment[iClient][iPunishmentType][i_id] = results.FetchInt(0);
		g_iPunishment[iClient][iPunishmentType][i_time] = results.FetchInt(3);
		g_iPunishment[iClient][iPunishmentType][i_timeremaining] = results.FetchInt(4);
		results.FetchString(5, g_sPunishment[iClient][iPunishmentType][s_reason], sizeof(g_sPunishment[][][]));
		g_bPunishment[iClient][iPunishmentType][b_active] = true;
		
		// Let the matching plugin know someone with this punishment joined
		Function fnJoin = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnJoin]);
		//Function fnJoin = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_join]);
		Call_StartFunction(g_hPunishmentType[iPunishmentType], fnJoin);
		Call_PushCell(iClient);
		Call_Finish();
	}
}

void InitializePunishmentType(int iPunishmentType, int iPunishmentTypeId)
{
	g_iPunishmentType[iPunishmentType][i_id] = iPunishmentTypeId;

	RegAdminCmd(g_sPunishmentType[iPunishmentType][s_startcommand], Command_StartPunishment, g_iPunishmentType[iPunishmentType][i_adminflags]);
	RegAdminCmd(g_sPunishmentType[iPunishmentType][s_stopcommand], Command_StopPunishment, g_iPunishmentType[iPunishmentType][i_adminflags]);
}

void GetPunishmentsForPunishmentType(int iPunishmentType)
{
	// Now let's get the punishment information of this type from the database for the players currently in the server
	char sIn[192];
	bool bFirst = true;

	// Loop over the people in the server already and check if they have a punishment of this type
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			int iClientId = Core_GetClientId(i);
			if (iClientId == -1)
			{
				// If we still can't get this player's id, skip it for now
				continue;
			}
			
			if (bFirst)
			{
				FormatEx(sIn, sizeof(sIn), "%d", iClientId);
				bFirst = false;
			}
			else
			{
				Format(sIn, sizeof(sIn), "%s,%d", sIn, iClientId);
			}
		}
	}

	// Only ask the database if there is someone in the server we can ask the details for
    // Ideally this'd also check by steamid but unfortunately that might not be entirely possible here
	if (!bFirst)
	{
		char sQuery[300];
		FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, `user_id`, `server_id`, `time`, `time_remaining`, `reason` FROM `punishments` WHERE `active` = 1 AND `punishment_type_id` = %d AND `user_id` IN (%s)", g_iPunishmentType[iPunishmentType][i_id], sIn);

		g_hDatabase.Query(SQL_Callback_PunishmentsForPunishmentType, sQuery, iPunishmentType, DBPrio_Normal);
	}
}

/********************************* Natives ***************************************/
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("TimedPunishment_RegisterPunishment", Native_RegisterPunishment);
	CreateNative("TimedPunishment_GetPunishmentInformation", Native_GetPunishmentInformation);
	return APLRes_Success;
}

public int Native_RegisterPunishment(Handle plugin, int numParams)
{
	char sStartCommand[sizeof(g_sPunishmentType[][])];

	// Arg 1 would be GetMyHandle() if we would work with GetFunctionByName;

	GetNativeString(1, sStartCommand, sizeof(sStartCommand));

	// Check if this punishment was registered already
	// @TODO: move finding a punishmenttype with this startcommand out of this function
	for (int i = 0; i < g_iEnabledPunishmentCount; i++)
	{
		if (StrEqual(g_sPunishmentType[i][s_startcommand], sStartCommand))
		{
			// The plugin that registered this punishment must've reloaded, set the plugin handle again to the reloaded plugin
			// and let it know of the currently active punishments
			//g_hPunishmentType[g_iEnabledPunishmentCount] = view_as<Handle>(GetNativeCell(1));
			g_hPunishmentType[g_iEnabledPunishmentCount] = plugin;

			GetPunishmentsForPunishmentType(i);

			return g_iPunishmentType[i][i_id];
		}
	}

	g_iPunishmentType[g_iEnabledPunishmentCount][i_id] = -1;
	//g_hPunishmentType[g_iEnabledPunishmentCount] = view_as<Handle>(GetNativeCell(1)); // @TODO: check, this might be possible without view_as
	g_hPunishmentType[g_iEnabledPunishmentCount] = plugin;
	g_sPunishmentType[g_iEnabledPunishmentCount][s_startcommand] = sStartCommand;
	GetNativeString(2, g_sPunishmentType[g_iEnabledPunishmentCount][s_stopcommand], sizeof(g_sPunishmentType[][]));
	GetNativeString(3, g_sPunishmentType[g_iEnabledPunishmentCount][s_name], sizeof(g_sPunishmentType[][]));
	g_iPunishmentType[g_iEnabledPunishmentCount][i_adminflags] = GetNativeCell(4);
	g_iPunishmentType[g_iEnabledPunishmentCount][i_countdownType] = GetNativeCell(5);
	g_bPunishmentType[g_iEnabledPunishmentCount][b_allowMultipleTargets] = view_as<bool>(GetNativeCell(6));
	g_bPunishmentType[g_iEnabledPunishmentCount][b_allowOtherServerPunishments] = view_as<bool>(GetNativeCell(7));
	GetNativeString(8, g_sPunishmentType[g_iEnabledPunishmentCount][s_fnStart], sizeof(g_sPunishmentType[][]));
	GetNativeString(9, g_sPunishmentType[g_iEnabledPunishmentCount][s_fnStop], sizeof(g_sPunishmentType[][]));
	GetNativeString(10, g_sPunishmentType[g_iEnabledPunishmentCount][s_fnJoin], sizeof(g_sPunishmentType[][]));
	GetNativeString(11, g_sPunishmentType[g_iEnabledPunishmentCount][s_fnLeave], sizeof(g_sPunishmentType[][]));

	/*Function fnStart = GetNativeFunction(8);
	Function fnStop = GetNativeFunction(9);
	Function fnJoin = GetNativeFunction(10);
	Function fnLeave = GetNativeFunction(11);
	g_fnPunishmentType[g_iEnabledPunishmentCount][fn_start] = view_as<PunishmentTypeCallback>(fnStart);
	g_fnPunishmentType[g_iEnabledPunishmentCount][fn_stop] = view_as<PunishmentTypeCallback>(fnStop);
	g_fnPunishmentType[g_iEnabledPunishmentCount][fn_join] = view_as<PunishmentTypeCallback>(fnJoin);
	g_fnPunishmentType[g_iEnabledPunishmentCount][fn_leave] = view_as<PunishmentTypeCallback>(fnLeave);*/

	if (g_hDatabase != null)
	{
		char sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "SELECT `id` FROM `punishment_types` WHERE `command` = '%s'", sStartCommand);

		g_hDatabase.Query(SQL_Callback_FetchPunishmentType, sQuery, g_iEnabledPunishmentCount, DBPrio_High);
	}

	// Tell the plugin what the current punishment is, and increment it AFTER doing that
	return g_iEnabledPunishmentCount++;
}

public int Native_GetPunishmentInformation(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int iPunishmentType = GetNativeCell(2);
	// @TODO: continue

	DataPack pack = new DataPack();

	/*if (!g_bPunishment[client][iPunishmentType][b_active])
	{
		pack
		return NO_PUNISHMENT_INFORMATION;
	}*/

	pack.WriteCell(g_bPunishment[client][iPunishmentType][b_active]);
	pack.WriteCell(g_iPunishment[client][iPunishmentType][i_time]);
	pack.WriteCell(g_iPunishment[client][iPunishmentType][i_timeremaining]);
	pack.WriteCell(g_iPunishment[client][iPunishmentType][i_timeStart]);
	pack.WriteString(g_sPunishment[client][iPunishmentType][s_reason]);
	
	DataPack pack_clone = view_as<DataPack>(CloneHandle(pack, plugin));

	return view_as<int>(pack_clone);
}

/***************************** Console commands **********************************/
public Action Command_StartPunishment(int client, int args)
{
	char sCommand[sizeof(g_sPunishmentType[][])]; int iPunishmentType;
	GetCmdArg(0, sCommand, sizeof(sCommand));


	
	for (int i = 0; i < g_iEnabledPunishmentCount; i++)
	{
		if (StrEqual(g_sPunishmentType[i][s_startcommand], sCommand, false))
		{
			iPunishmentType = i;
			break;
		}
	}

	if (args < 1)
	{
		// @TODO: Show player menu with code preferrably in the core (see damagelog code), we need one for the admin menu anyways
        // @TODO: use AddTargetsToMenu
		return Plugin_Handled;
	}

	char sArg[255]; char sTarget[MAX_NAME_LENGTH];
	GetCmdArgString(sArg, sizeof(sArg));
	//GetCmdArg(1, sArg, sizeof(sArg));

	int iLen = BreakString(sArg, sTarget, sizeof(sTarget));

	int iTargetCount; int targets[MAXPLAYERS+1]; char sTargetName[MAX_NAME_LENGTH]; char sSteamid64[32]; bool tn_is_ml;

	if (String_StartsWith(sTarget, "STEAM_"))
	{
		//char sSteamid[32];
		//strcopy(sSteamid, sizeof(sSteamid), sArg);
		/*if (strlen(sTarget) == 7 && args >= 5)
		{
			// This should be longer, we don't have complete steamid yet
			char sAuthidPart1[2]; char sAuthidPart2[16];
			iLen += GetCmdArg(3, sAuthidPart1, sizeof(sAuthidPart1)) + GetCmdArg(5, sAuthidPart2, sizeof(sAuthidPart2)) + 2;           
			FormatEx(sTargetName, sizeof(sTargetName), "STEAM_1:%s:%s", sAuthidPart1, sAuthidPart2);
		}
		else
		{*/
		sTargetName = sTarget;
		//}

		//targets[0] = GetClientOfAuthId(sSteamid);
		targets[0] = GetClientOfAuthId(sTargetName);
		iTargetCount = 1;

		if (targets[0] == -1)
		{
			//GetCommunityID(sTargetName, sSteamid64, sizeof(sSteamid64));
			//sTargetName = sSteamid;
			GetCommunityID(sTargetName, sSteamid64, sizeof(sSteamid64));
		}
		else
		{
			GetClientName(targets[0], sTargetName, sizeof(sTargetName));
		}
	}
	else
	{
		int iMaxTargets = g_bPunishmentType[iPunishmentType][b_allowMultipleTargets] ? MaxClients : 1;
		int iCommandTargetFlags = COMMAND_FILTER_NO_BOTS;

		if (!g_bPunishmentType[iPunishmentType][b_allowMultipleTargets])
		{
			iCommandTargetFlags = iCommandTargetFlags | COMMAND_FILTER_NO_MULTI;
		}

		iTargetCount = Core_ProcessTargetString(sTarget, client, targets, iMaxTargets, iCommandTargetFlags, sTargetName, sizeof(sTargetName), tn_is_ml);

		if (iTargetCount <= 0)
		{
			ReplyToTargetError(client, iTargetCount);
			return Plugin_Handled;
		}
	}
	
	int iTime;
	
	if (iLen != -1)
	{
		char sTime[32];
		int iTimeLength = BreakString(sArg[iLen], sTime, sizeof(sTime));
		iTime = StringToInt(sTime);
		
		if (iTime != 0 || (strlen(sTime) == 1 && IsCharNumeric(sTime[0])))
		{
			// A time was passed as an argument
			iLen += iTimeLength;
		}
	}
	else
	{
		iLen = strlen(sArg);
	}

	// Get the reason and time and put them inside the variables
	/*if (args > 1)
	{
		// Try to get the name
		GetCmdArg(2, sArg, sizeof(sArg));
		iTime = StringToInt(sArg);

		int iReasonStartArg;

		if (iTime == 0 && (strlen(sArg) > 1 || !IsCharNumeric(sArg[0])))
		{
			// No time was passed as an argument, so we immediately got the reason next
			iReasonStartArg = 2;
		}
		else
		{
			iReasonStartArg = 3;
		}

		//BreakString(); // credits: sourcebans

		//for (int i = iReasonStartArg; i <= args; i++)
		//{
		//	GetCmdArg(i, sArg, sizeof(sArg));
		//	Format(sReason, sizeof(sReason), "%s %s", sReason, sArg);
		//	
		//	// Remove whitespace from start/end of reason
		//	TrimString(sReason);
		//}
	}*/

	if (iTargetCount == 1)
	{
		int iTargetClient = targets[0];
		int iTargetClientId;

		if (iTargetClient != -1)
		{
			if (g_bPunishment[iTargetClient][iPunishmentType][b_active] && !g_bPunishment[iTargetClient][iPunishmentType][b_wasMultiTarget])
			{
				// If we already have an active punishment that isn't temporary for this client, we can't override it
				ReplyToCommand(client, "%s already has an active non-temporary %s, cannot override it.", sTargetName, g_sPunishmentType[iPunishmentType][s_name]);
				return Plugin_Handled;
			}
			
			GetClientAuthId(iTargetClient, AuthId_SteamID64, sSteamid64, sizeof(sSteamid64));
			iTargetClientId = Core_GetClientId(iTargetClient);

			// We should save it
			g_iPunishment[iTargetClient][iPunishmentType][i_id] = -1;
			g_iPunishment[iTargetClient][iPunishmentType][i_time] = iTime;
			g_iPunishment[iTargetClient][iPunishmentType][i_timeremaining] = iTime;
			g_iPunishment[iTargetClient][iPunishmentType][i_timeStart] = GetTime();
			g_iPunishment[iTargetClient][iPunishmentType][i_admin] = client;
			g_bPunishment[iTargetClient][iPunishmentType][b_active] = true;
			g_bPunishment[iTargetClient][iPunishmentType][b_wasMultiTarget] = false;
			strcopy(g_sPunishment[iTargetClient][iPunishmentType][s_reason], sizeof(g_sPunishment[][][]), sArg[iLen]);
			//g_sPunishment[iTargetClient][iPunishmentType][s_reason] = sArg[iLen];

			Function fnStart = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnStart]);
			//Function fnStart = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_start]);
			Call_StartFunction(g_hPunishmentType[iPunishmentType], fnStart);
			Call_PushCell(iTargetClient);
			Call_Finish();
		}


		char sEscapedReason[512];
		//g_hDatabase.Escape(sReason, sEscapedReason, sizeof(sEscapedReason));
		g_hDatabase.Escape(sArg[iLen], sEscapedReason, strlen(sEscapedReason));

		// @TODO: start database query? Probably not necessary since we will save it on disconnect. Savest to do it here first
		char sQuery[512];
		Format(sQuery, sizeof(sQuery), "INSERT INTO `punishments` (`punishment_type_id`, `user_id`, `steamid64`, `server_id`, `admin_id`, `reason`, `time`, `time_remaining`, `active`, `created_at`) VALUES (%d, %d, %s, %d, %d, '%s', %d, %d, 1, CURRENT_TIMESTAMP)", g_iPunishmentType[iPunishmentType][i_id], iTargetClientId, sSteamid64, g_iServer, Core_GetClientId(client), sEscapedReason, iTime, iTime);

		int iUserId = iTargetClient ? GetClientUserId(iTargetClient) : -1;
		
		DataPack dPack = new DataPack();
		dPack.WriteCell(iUserId);
		dPack.WriteCell(iPunishmentType);

		g_hDatabase.Query(SQL_Callback_InsertPunishment, sQuery, dPack, DBPrio_High); // @TODO: might have to make this a bit safer and give the punishment itself an id? Dunno. Also might have to pass PunishmentType
	}
	else
	{
		// We have multiple targets
		for (int i = 0; i < iTargetCount; i++)
		{
			int iTargetClient = targets[i];
			
			if (g_bPunishment[iTargetClient][iPunishmentType][b_active] && !g_bPunishment[iTargetClient][iPunishmentType][b_wasMultiTarget])
			{
				// If we already have an active punishment that isn't temporary, ignore this iTargetClient
				continue;
			}
			
			g_iPunishment[iTargetClient][iPunishmentType][i_id] = -1;
			g_iPunishment[iTargetClient][iPunishmentType][i_time] = -1;
			g_iPunishment[iTargetClient][iPunishmentType][i_timeremaining] = -1;
			g_iPunishment[iTargetClient][iPunishmentType][i_admin] = client;
			//g_iPunishment[iTargetClient][iPunishmentType][i_countdownType]
			g_iPunishment[iTargetClient][iPunishmentType][i_timeStart] = GetTime();
			g_bPunishment[iTargetClient][iPunishmentType][b_active] = true;
			g_bPunishment[iTargetClient][iPunishmentType][b_wasMultiTarget] = true;
			strcopy(g_sPunishment[iTargetClient][iPunishmentType][s_reason], sizeof(g_sPunishment[][][]), sArg[iLen]);
			//g_sPunishment[iTargetClient][iPunishmentType][s_reason] = sArg[iLen];
			
			Function fnStart = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnStart]);
			//Function fnStart = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_start]);
			Call_StartFunction(g_hPunishmentType[iPunishmentType], fnStart);
			Call_PushCell(iTargetClient);
			Call_Finish();
			
			// Don't save this one in the database
		}
	}

	char sShowReason[255]; char sShowTime[25];
	if (sArg[iLen] != 0)
	//if (strlen(sArg[iLen]) != 0)
	{
		// Is the reason not empty?
		Format(sShowReason, sizeof(sShowReason), " Reason: %s", sArg[iLen]);
	}

	if (iTime == 0)
	{
		// Is the time permanent or until mapchange?
		sShowTime = iTargetCount > 1 ? "until mapchange" : "for all eternity";
	}
	else
	{
		Format(sShowTime, sizeof(sShowTime), "for %d minutes", iTime);
	}

	if (tn_is_ml)
	{
		Core_ShowActivity2(client, "[SM] ", "Started a %s on %t %s.%s", g_sPunishmentType[iPunishmentType][s_name], sTargetName, sShowTime, sShowReason);
	}
	else
	{
		Core_ShowActivity2(client, "[SM] ", "Started a %s on %s %s.%s", g_sPunishmentType[iPunishmentType][s_name], sTargetName, sShowTime, sShowReason);
	}

	return Plugin_Handled;
}

public Action Command_StopPunishment(int client, int args)
{
	char sCommand[sizeof(g_sPunishmentType[][])]; int iPunishmentType;
	GetCmdArg(0, sCommand, sizeof(sCommand));
	
	for (int i = 0; i < g_iEnabledPunishmentCount; i++)
	{
		if (StrEqual(g_sPunishmentType[i][s_stopcommand], sCommand, false))
		{
			iPunishmentType = i;
			break;
		}
	}
	
	if (args < 1)
	{
		// @TODO: Show player menu (see damagelog code)
		return Plugin_Handled;
	}
	
	char sArg[32];
	GetCmdArg(1, sArg, sizeof(sArg));
	
	int targets[MAXPLAYERS+1]; char sTargetName[MAX_NAME_LENGTH]; bool tn_is_ml;
	
	int max_targets = g_bPunishmentType[iPunishmentType][b_allowMultipleTargets] ? MaxClients : 1;
	int iCommandTargetFlags = COMMAND_FILTER_NO_BOTS;
	
	if (!g_bPunishmentType[iPunishmentType][b_allowMultipleTargets])
	{
		iCommandTargetFlags = iCommandTargetFlags | COMMAND_FILTER_NO_MULTI;
	}
	
	
	int iTargetCount = Core_ProcessTargetString(sArg, client, targets, max_targets, iCommandTargetFlags, sTargetName, sizeof(sTargetName), tn_is_ml);

	if (iTargetCount <= 0)
	{
		ReplyToTargetError(client, iTargetCount);
		return Plugin_Handled;
	}
	
	char sReason[sizeof(g_sPunishment[][][])];
	
	// Get the reason and time and put them inside the variables
	if (args > 1)
	{
		// Try to get the name
		GetCmdArg(2, sArg, sizeof(sArg));

		int iReasonStartArg = 2;
		
		for (int i = iReasonStartArg; i <= args; i++)
		{
			GetCmdArg(i, sArg, sizeof(sArg));
			Format(sReason, sizeof(sReason), "%s %s", sReason, sArg);
			
			// Remove whitespace from start/end of reason
			TrimString(sReason);
		}
	}
	
	if (iTargetCount == 1)
	{
		int iTargetClient = targets[0];

		if (!g_bPunishment[iTargetClient][iPunishmentType][b_active])
		{
			// This player has no active punishment of this type
			ReplyToCommand(client, "Player %s has no active %s currently.", sTargetName, g_sPunishmentType[iPunishmentType][s_name]);
			return Plugin_Handled;
		}
	
		RemovePunishment(iTargetClient, iPunishmentType, client, sReason);
		
		Function fnStop = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnStop]);
		//Function fnStop = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_stop]);
		Call_StartFunction(g_hPunishmentType[iPunishmentType], fnStop);
		Call_PushCell(iTargetClient);
		Call_Finish();
	}
	else
	{
		// We have multiple targets
		for (int i = 0; i < iTargetCount; i++)
		{
			int iTargetClient = targets[i];
			
			// @TODO: check
			if (!g_bPunishment[iTargetClient][iPunishmentType][b_active] || !g_bPunishment[iTargetClient][iPunishmentType][b_wasMultiTarget])
			{
				// This player has no active temporary punishment of this type
			    continue;
			}
			
			RemovePunishment(iTargetClient, iPunishmentType, client, sReason);
			
			Function fnStop = GetFunctionByName(g_hPunishmentType[iPunishmentType], g_sPunishmentType[iPunishmentType][s_fnStop]);
			//Function fnStop = view_as<Function>(g_fnPunishmentType[iPunishmentType][fn_stop]);
			Call_StartFunction(g_hPunishmentType[iPunishmentType], fnStop);
			Call_PushCell(iTargetClient);
			Call_Finish();
        }
	}
	
	char sShowReason[255];
	if (sReason[0] != 0)
	{
		// Is the reason not empty?
		Format(sShowReason, sizeof(sShowReason), " Reason: %s", sReason);
	}
	
	if (tn_is_ml)
	{
		Core_ShowActivity2(client, "[SM] ", "Removed a %s from %t.%s", g_sPunishmentType[iPunishmentType][s_name], sTargetName, sShowReason);
	}
	else
	{
		Core_ShowActivity2(client, "[SM] ", "Removed a %s from %s.%s", g_sPunishmentType[iPunishmentType][s_name], sTargetName, sShowReason);
	}

	return Plugin_Handled;
}

public Action Command_MyPunishments(int client, int args)
{
    ShowActivePunishments(client, client);
    return Plugin_Handled;
}

public Action Command_CheckPunishments(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_checkpunishments <name or #userid>");
		return Plugin_Handled;
	}

	char sArg[MAX_NAME_LENGTH];
	GetCmdArg(1, sArg, sizeof(sArg));
	int target = FindTarget(client, sArg, true, false);
	if (target == -1)
	{
		return Plugin_Handled;
	}

	ShowActivePunishments(target, client);

	return Plugin_Handled;
}

void ShowActivePunishments(int target, int client)
{
	// @TODO: allow clicking on specific punishments for more information
    Menu menu = new Menu(MenuHandler_ShowActivePunishments);
    //menu.ExitBackButton = true;
    menu.SetTitle("Active punishments on %N", target);
    
    char sTime[32];
    char sFormat[64];
    
    for (int i = 0; i < g_iEnabledPunishmentCount; i++)
    {
        if (!g_bPunishment[target][i][b_active])
        {
            continue;
        }
        
        char sCountdownType[32];
        
        // @TODO: move time formatting to seperate function
        
        if (g_iPunishment[target][i][i_timeremaining] != 0)
        {
            FormatEx(sTime, sizeof(sTime), "%d minutes", g_iPunishment[target][i][i_timeremaining]);
            GetCountdownString(sCountdownType, sizeof(sCountdownType), i);
        }
        else if (g_bPunishment[target][i][b_wasMultiTarget] || g_iPunishmentType[i][i_countdownType] == COUNTDOWN_CURRENTMAP)
        {
            FormatEx(sTime, sizeof(sTime), "untill mapchange (temporary)");
        }
        else
        {
            FormatEx(sTime, sizeof(sTime), "permanent");
            GetCountdownString(sCountdownType, sizeof(sCountdownType), i);
        }
        
        FormatEx(sFormat, sizeof(sFormat), "%s - %s %s", g_sPunishmentType[i][s_name], sTime, sCountdownType);
        
        menu.AddItem(sFormat, sFormat, ITEMDRAW_DISABLED);
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
}

void GetCountdownString(char[] sBuffer, int iBufferSize, int iPunishmentType)
{
    switch (iPunishmentType)
    {
        //case COUNTDOWN_CONSTANT:
		//{
		//    FormatEx(sBuffer, sizeof(sBuffer), "")
		//}
        case COUNTDOWN_ONLINE:
		{
			FormatEx(sBuffer, iBufferSize, "online");
		}
        case COUNTDOWN_ALIVE:
		{
			FormatEx(sBuffer, iBufferSize, "alive");
		}
        //case COUNTDOWN_CURRENTMAP:
		//{
        //    FormatEx(sBuffer, iBufferSize, "current map")
		//}
        default:
		{
            FormatEx(sBuffer, iBufferSize, "");
		}
    }
}

public int MenuHandler_ShowActivePunishments(Menu menu, MenuAction action, int param1, int param2)
{
	/* If the menu has ended, destroy it */
	if (action == MenuAction_End)
	{
		delete menu;
	}
}