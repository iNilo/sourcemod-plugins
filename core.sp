#include <sourcemod>
#include <cnf_core>

#pragma semicolon 1
#pragma newdecls required

enum ClientInfoInt
{
	i_id,
	i_nameprocessed
}

enum ClientInfoString
{
	s_name,
	s_processedname,
	s_steamid64
}

//#define MAX_QUERY_CACHE 2048

// @TODO: Fire forward for server id!
// Colors: https://forums.alliedmods.net/showthread.php?t=281278 start with \x01\x03
// @POSSIBLE TODO: change ip to long ip since it might be faster for MySQL

Database g_hDatabase = null;

Handle g_hConnectionEstablished = null;
Handle g_hClientFullyConnected = null;
Handle g_hServerConnected = null;
Handle g_hFirstJoin = null;
Handle g_hClientPutInServer = null;

//char g_sQueryCache[MAX_QUERY_CACHE];

int g_iServer = -1;

bool g_bIsUndercover[MAXPLAYERS+1];
bool g_bIsGhost[MAXPLAYERS+1];
bool g_bConnectionErrorLogged = false;
bool g_bFirstConnection = true;

//int g_iCurrentQuery;

// @TODO: add server id support

int g_iClient[MAXPLAYERS+1] = {-1,...};

ConVar g_Cvar_hostip;
ConVar g_Cvar_hostport;

char g_sIp[16];
int g_iPort;

public Plugin myinfo =
{
	name = "Main native core",
	author = "Meitis",
	description = "This plugin handles all core-functions used by the server",
	version = "0.1",
	url = ""
}

public void OnPluginStart()
{
	HookConvars();
	
	SetTargetFilters();
	CreateForwards();
	HookEvents();
	
	
	ConnectToDatabase();
	CreateTimer(120.0, Timer_DatabaseConnect, _, TIMER_REPEAT);
}

void HookConvars()
{
	g_Cvar_hostip = FindConVar("hostip");
	g_Cvar_hostport = FindConVar("hostport");
}

public void CreateForwards()
{
	g_hConnectionEstablished = CreateGlobalForward("Core_OnConnectionEstablished", ET_Ignore);
	g_hServerConnected = CreateGlobalForward("Core_OnServerConnected", ET_Ignore, Param_Cell);
	g_hClientFullyConnected = CreateGlobalForward("Core_OnClientPostAdminCheck", ET_Ignore, Param_Cell, Param_Cell);
	g_hFirstJoin = CreateGlobalForward("Core_OnFirstJoin", ET_Ignore, Param_Cell);
	g_hClientPutInServer = CreateGlobalForward("Core_OnClientPutInServer", ET_Ignore, Param_Cell);
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsFakeClient(client) && !IsClientSourceTV(client) && GetClientTime(client) <= GetGameTime())
	{ 
		// The client only just connected and didn't play last map
		FetchClientId(client);
	}
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client) && !IsClientSourceTV(client) && GetClientTime(client) <= GetGameTime())
	{ 
		// Let the plugins know this player just joined without playing the previous map
		Call_StartForward(g_hClientPutInServer);
		Call_PushCell(client);
		Call_Finish();
	}
}

public void FetchClientId(int client)
{
	if (g_hDatabase != null)
	{
		// This assumes the player_disconnect event will always be called when leaving
		if (g_iClient[client] == -1)
		{
			char steamid64[32]; char query[100];
			//GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
			GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
			int userid = GetClientUserId(client);
			
			//FormatEx(query, sizeof(query), "SELECT `id` FROM `users` WHERE `authid` = '%s'", steamid[8]);
			FormatEx(query, sizeof(query), "SELECT `id` FROM `users` WHERE `steamid64` = %s", steamid64);
			
			g_hDatabase.Query(SQL_PlayerConnected, query, userid, DBPrio_High);
		}
	}
}

/*********************************** Events ***********************************/
public void HookEvents()
{
	HookEvent("player_disconnect", Event_PlayerDisconnect);
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client)
	{
		g_iClient[client] = -1;
	}
}

public void ClientConnected(int iClient, int iClientId)
{
	g_iClient[iClient] = iClientId;
	
	// Fire client connected forward
	Call_StartForward(g_hClientFullyConnected);
	Call_PushCell(iClient);
	Call_PushCell(iClientId);
	Call_Finish();
}

void ServerConnected(int iServerId)
{
	g_bFirstConnection = false;
	g_iServer = iServerId;
	
	// Fire client connected forward
	Call_StartForward(g_hServerConnected);
	Call_PushCell(g_iServer);
	Call_Finish();
}

/*********************************** Natives ***********************************/
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Core_GetDatabase", Native_GetDatabase);
	CreateNative("Core_IsPlayerAlive", Native_IsPlayerAlive);
	CreateNative("Core_SendAdminActivity", Native_SendAdminActivity);
	CreateNative("Core_GetClientId", Native_GetClientId);
	CreateNative("Core_GetClientOfClientId", Native_GetClientOfClientId);
	CreateNative("Core_GetServerId", Native_GetServerId);
	//CreateNative("Core_SetClanTag", Native_SetClanTag);
	CreateNative("Core_ProcessTargetString", Native_ProcessTargetString);

	return APLRes_Success;
}

public int Native_GetDatabase(Handle plugin, int numParams)
{
	if (g_hDatabase == null)
	{
		return view_as<int>(INVALID_HANDLE);
	}
	
	return view_as<int>(CloneHandle(g_hDatabase, plugin));
}

public int Native_GetServerId(Handle plugin, int numParams)
{
	return g_iServer;
}

public int Native_IsPlayerAlive(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return IsClientInGame(client) && IsPlayerAlive(client) && !g_bIsGhost[client];
}

public int Native_ProcessTargetString(Handle plugin, int numParams)
{
	char pattern[128]; char target_name[MAX_NAME_LENGTH]; int iPlayerCount;
	
	GetNativeString(1, pattern, sizeof(pattern));
	int admin = GetNativeCell(2);
	int iMaxTargets = GetNativeCell(4);
	int[] targets = new int[iMaxTargets];
	GetNativeArray(3, targets, iMaxTargets);
	int filter_flags = GetNativeCell(5);
	GetNativeString(6, target_name, sizeof(target_name));
	int tn_maxlength = GetNativeCell(7);
	bool tn_is_ml = GetNativeCellRef(8);
	
	if (!(filter_flags & COMMAND_FILTER_NO_MULTI))
	{
		if (StrEqual("@alive", pattern))
		{
			target_name = "all alive players";
			tn_is_ml = true;
			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i) || !Core_IsPlayerAlive(i) || !((filter_flags & COMMAND_FILTER_NO_IMMUNITY) || CanUserTarget(admin, i)))
				{
					continue;
				}
				
				targets[iPlayerCount] = i;
				iPlayerCount++;
				
				if (iPlayerCount > iMaxTargets)
				{
					return COMMAND_TARGET_AMBIGUOUS;
				}
			}
			//return iPlayerCount ? iPlayerCount : COMMAND_TARGET_EMPTY_FILTER;
		}
		if (StrEqual("@dead", pattern))
		{
			target_name = "all dead players";
			tn_is_ml = true;
			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsClientInGame(i) || Core_IsPlayerAlive(i)  || !((filter_flags & COMMAND_FILTER_NO_IMMUNITY) || CanUserTarget(admin, i)))
				{
					continue;
				}
				
				targets[iPlayerCount] = i;
				iPlayerCount++;
				
				if (iPlayerCount > iMaxTargets)
				{
					return COMMAND_TARGET_AMBIGUOUS;
				}
			}
			//return iPlayerCount ? iPlayerCount : COMMAND_TARGET_EMPTY_FILTER;
		}
	}
	
	if (iPlayerCount <= 0)
	{
		iPlayerCount = ProcessTargetString(pattern, admin, targets, iMaxTargets, filter_flags, target_name, tn_maxlength, tn_is_ml);
	}
	
	if (iPlayerCount <= 0)
	{
		// Check the simplified names
		for (int i = 1; i <= MaxClients; i++)
		{
			// if (isClientInGame(i) && StrContains(g_sClient[i][s_targetname], pattern, ) != -1)
            // {
            // }
		}
	}
	
	SetNativeArray(3, targets, iMaxTargets);
	SetNativeString(6, target_name, sizeof(target_name));
	SetNativeCellRef(8,tn_is_ml);
	
	return iPlayerCount;
}

public int Native_SendAdminActivity(Handle plugin, int numParams)
{
	int len;

	int admin = GetNativeCell(1);
	
	GetNativeStringLength(2, len);
	char[] tag = new char[len + 1];
	GetNativeString(2, tag, len + 1);
	
	GetNativeStringLength(3, len);
	char[] message = new char[len + 1];
	GetNativeString(3, message, len + 1);
	
	if (g_bIsUndercover[admin])
	{
		// Send it just to admins
		LogMessage("[AdminOnly] %s %N did %s", tag, admin, message);
	} else {
		ShowActivity2(admin, tag, message);
	}
}

public int Native_GetClientId(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return client == 0 ? 0 : g_iClient[client];
}

public int Native_GetClientOfClientId(Handle plugin, int numParams)
{
	int iClientId = GetNativeCell(1);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && iClientId == g_iClient[i])
		{
			return i;
		}
	}
	
	return -1;
}


/*********************************** Database ***********************************/
public void ConnectToDatabase()
{
	// Let's only have one place where we define the default connection argument :p
	if (SQL_CheckConfig("core"))
	{
		Database.Connect(SQL_OnDatabaseConnect, "core");
	} else {
		Database.Connect(SQL_OnDatabaseConnect, "default");
	}
}

public Action Timer_DatabaseConnect(Handle timer, any data)
{
	if (g_hDatabase == null)
	{
		ConnectToDatabase();
	}
	return Plugin_Continue;
}

public void SQL_OnDatabaseConnect(Database db, const char[] error, any data)
{
	// If we already managed to get a connection in the meantime, ignore it.
	if (g_hDatabase != null)
	{
		delete db;
		return;
	}
	
	// If this connection failed and no previous one did, log the issue.
	if (db == null)
	{
		if (!g_bConnectionErrorLogged)
		{
			g_bConnectionErrorLogged = true;
			LogError("Failed to connect to database: %s", error);
		}
		return;
	}
	
	g_hDatabase = db;
	g_bConnectionErrorLogged = false;
	
	//LogMessage("Database connection established");
	
	if (g_bFirstConnection)
	{
		char query[256];
		LongToIp(g_Cvar_hostip.IntValue, g_sIp, sizeof(g_sIp));
		g_iPort = g_Cvar_hostport.IntValue;
		FormatEx(query, sizeof(query), "SELECT `id` FROM `servers` WHERE `ip` = '%s' AND `port` = %d", g_sIp, g_iPort);
		g_hDatabase.Query(SQL_FetchServerId, query, _, DBPrio_High);
	}
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && g_iClient[client] == -1)
		{
			// We don't have this user's clientid yet, fetch it
			FetchClientId(client);
		}
	}
	
	// Fire connection established forward
	Call_StartForward(g_hConnectionEstablished);
	Call_Finish();
	
	// Go through queue?
}

public void SQL_FetchServerId(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null)
	{
		// We had an error, log it
		LogError("Could not get the serverid: %s", error);
		return;
	}
	
	if (results.FetchRow())
	{
		// Server was registered already
		// Fire forward so other plugins know it?
		ServerConnected(results.FetchInt(0));
	}
	else
	{
		char sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `servers` (`ip`, `port`) VALUES ('%s', %d)", g_sIp, g_iPort);
		g_hDatabase.Query(SQL_ServerConnected, sQuery, _, DBPrio_High);
	}
}

public void SQL_ServerConnected(Database db, DBResultSet results, const char[] sError, any data)
{
	if (db == null || strlen(sError) != 0)
	{
		// We had an error, log it
		LogError("Could not insert the serverid: %s", sError);
		return;
	}
	
	// Fire forward?
	ServerConnected(results.InsertId);
}

public void SQL_PlayerConnected(Database db, DBResultSet results, const char[] sError, any userid)
{
	if (db == null || strlen(sError) != 0)
	{
		// We had an error, log it
		LogError("Could not get the clientid for one of the users: %s", sError);
		return;
	}
	
	int client = GetClientOfUserId(userid);
	
	if (client == 0 || g_iClient[client] != -1)
	{
		// The user is no longer on the server or we already have his id, abort
		return;
	}
	
	if (results.FetchRow())
	{
		// The user was in the database, so let's get his client id
		ClientConnected(client, results.FetchInt(0));
	}
	else if (g_hDatabase != null)
	{
		// The user is new and we have a database connection, let's save him
		// @TODO: consider changing MAX_NAME_LENGTH to a 128 character define, since that's what CSGO uses internally
		// Steam max is 32 characters but multibyte is possible
		char query[100]; char steamid64[32]; char name[MAX_NAME_LENGTH]; char escaped_name[(MAX_NAME_LENGTH*2)-1];
		//GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		GetClientAuthId(client, AuthId_SteamID64, steamid64, sizeof(steamid64));
		GetClientName(client, name, sizeof(name));
		
		g_hDatabase.Escape(name, escaped_name, sizeof(name));
		
		//FormatEx(query, sizeof(query), "INSERT INTO `users` (`name`, `authid`, `steamid64`) VALUES('%s','%s', %s)", escaped_name, steamid[8], steamid64);
		FormatEx(query, sizeof(query), "INSERT INTO `users` (`name`, `steamid64`) VALUES('%s', %s)", escaped_name, steamid64);
		g_hDatabase.Query(SQL_NewPlayer, query, userid, DBPrio_High);
	}
}

public void SQL_NewPlayer(Database db, DBResultSet results, const char[] sError, any userid)
{
	if (db == null || strlen(sError) != 0)
	{
		// We had an error, log it
		LogError("Could not add the clientid for one of the users: %s", sError);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (client == 0 || g_iClient[client] != -1)
	{
		// The user is no longer on the server or we already have his id, abort
		return;
	}

	// Client got inserted successfully so let's let every plugin know
	ClientConnected(client, results.InsertId);

	// Fire connection established forward
	Call_StartForward(g_hFirstJoin);
	Call_PushCell(client);
	Call_Finish();
}

/*********************************** Stocks ***********************************/
stock void LongToIp(int binary, char[] address, int maxlength)
{
	int quads[4];
	quads[0] = binary >> 24 & 0x000000FF; // mask isn't necessary for this one, but do it anyway
	quads[1] = binary >> 16 & 0x000000FF;
	quads[2] = binary >> 8 & 0x000000FF;
	quads[3] = binary & 0x000000FF;
	
	Format(address, maxlength, "%d.%d.%d.%d", quads[0], quads[1], quads[2], quads[3]);
}

/***************************** Target filters ******************************/
void SetTargetFilters()
{
	// http://ddhoward.bitbucket.org/scripting/namechangeinfo.sp
}