#include <sourcemod>
#include <sdktools>
//#include <smlib>
#include <cnf_core>
#include <mapvariables>

#define MAXMAPVARIABLES 32
#define MAXMAPVARIABLESTRING 32

enum MapVariableString {
    s_key,
    s_value
};

StringMap g_smMapVariables = null;

char g_sMapVariable[MAXMAPVARIABLES][MapVariableString][MAXMAPVARIABLESTRING];
int g_iId[MAXMAPVARIABLES];
bool g_bChanged[MAXMAPVARIABLES];

int g_iMap = -1;
int g_iServer = -1;

Handle g_hMapVariablesFetched = null;

Database g_hDatabase = null;

int g_iKeyCount = 0;
int g_iChanged = 0;

int g_iTime = 0;

public void OnPluginStart()
{
	g_smMapVariables = CreateTrie();

	g_hMapVariablesFetched = CreateGlobalForward("OnMapVariablesFetched", ET_Ignore);

	g_hDatabase = Core_GetDatabase();
	g_iServer = Core_GetServerId();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("GetMapVariableString", Native_GetMapVariableString);
	CreateNative("GetMapVariableFloat", Native_GetMapVariableFloat);
	CreateNative("GetMapVariableInt", Native_GetMapVariableInt);
	CreateNative("SetMapVariableString", Native_SetMapVariableString);
	CreateNative("SetMapVariableFloat", Native_SetMapVariableFloat);
	CreateNative("SetMapVariableInt", Native_SetMapVariableInt);

	return APLRes_Success;
}

public int Native_GetMapVariableString(Handle plugin, int numParams)
{
	char sKey[MAXMAPVARIABLESTRING]; int iKeyIndex;
	GetNativeString(1, sKey, sizeof(sKey));

	if (!g_smMapVariables.GetValue(sKey, iKeyIndex))
	{
		return NO_MAPVARIABLE_AVAILABLE;
	}
	
	int iLength = GetNativeCell(3);
	
	return SetNativeString(2, g_sMapVariable[iKeyIndex][s_value], iLength);
}

public int Native_GetMapVariableInt(Handle plugin, int numParams)
{
	char sKey[MAXMAPVARIABLESTRING]; int iKeyIndex;
	GetNativeString(1, sKey, sizeof(sKey));

	if (g_smMapVariables.GetValue(sKey, iKeyIndex))
	{
        return SetNativeCellRef(2, StringToInt(g_sMapVariable[iKeyIndex][s_value]));
		//return StringToInt(g_sMapVariable[iKeyIndex][s_value]);
	}

	return NO_MAPVARIABLE_AVAILABLE;
}

public int Native_GetMapVariableFloat(Handle plugin, int numParams)
{
	char sKey[MAXMAPVARIABLESTRING]; int iKeyIndex;
	GetNativeString(1, sKey, sizeof(sKey));

	if (g_smMapVariables.GetValue(sKey, iKeyIndex))
	{
		SetNativeCellRef(2, StringToFloat(g_sMapVariable[iKeyIndex][s_value]));
		//return view_as<int>(StringToFloat(g_sMapVariable[iKeyIndex][s_value]));
		return 1;
	}

	return NO_MAPVARIABLE_AVAILABLE;
}

public int Native_SetMapVariableString(Handle plugin, int numParams)
{
	char sKey[MAXMAPVARIABLESTRING]; int iKeyIndex;
	GetNativeString(1, sKey, sizeof(sKey));

	if (g_smMapVariables.GetValue(sKey, iKeyIndex))
	{
		// We already have it, update it
		GetNativeString(2, g_sMapVariable[iKeyIndex][s_value], MAXMAPVARIABLESTRING);

		if (!g_bChanged[iKeyIndex])
		{
			g_bChanged[iKeyIndex] = true;
			g_iChanged++;
		}

		return iKeyIndex;
	}

	if (g_iKeyCount < MAXMAPVARIABLES)
	{
		iKeyIndex = g_iKeyCount;
		GetNativeString(2, g_sMapVariable[iKeyIndex][s_value], MAXMAPVARIABLESTRING);
		g_sMapVariable[iKeyIndex][s_key] = sKey;
		g_iId[iKeyIndex] = -1;
		g_bChanged[iKeyIndex] = true;
		g_iChanged++;
		g_smMapVariables.SetValue(sKey, iKeyIndex);
		g_iKeyCount++;
		return iKeyIndex;
	}

	return -1;
}

public int Native_SetMapVariableInt(Handle plugin, int numParams)
{
	char sKey[MAXMAPVARIABLESTRING]; int iKeyIndex;
	GetNativeString(1, sKey, sizeof(sKey));

	if (g_smMapVariables.GetValue(sKey, iKeyIndex))
	{
		// We already have it, update it
		int iValue = GetNativeCell(2);
		IntToString(iValue, g_sMapVariable[iKeyIndex][s_value], MAXMAPVARIABLESTRING);

		if (!g_bChanged[iKeyIndex])
		{
			g_bChanged[iKeyIndex] = true;
			g_iChanged++;
		}

		return iKeyIndex;
	}

	if (g_iKeyCount < MAXMAPVARIABLES)
	{
		iKeyIndex = g_iKeyCount
		int iValue = GetNativeCell(2);
		IntToString(iValue, g_sMapVariable[iKeyIndex][s_value], MAXMAPVARIABLESTRING);
		g_sMapVariable[iKeyIndex][s_key] = sKey;
		g_iId[iKeyIndex] = -1;
		g_bChanged[iKeyIndex] = true;
		g_iChanged++;
		g_smMapVariables.SetValue(sKey, iKeyIndex);
		g_iKeyCount++;
		return iKeyIndex;
	}

	return -1;
}

public int Native_SetMapVariableFloat(Handle plugin, int numParams)
{
	char sKey[MAXMAPVARIABLESTRING]; int iKeyIndex;
	GetNativeString(1, sKey, sizeof(sKey));

	if (g_smMapVariables.GetValue(sKey, iKeyIndex))
	{
		// We already have it, update it
		float fValue = view_as<float>(GetNativeCell(2));
		FloatToString(fValue, g_sMapVariable[iKeyIndex][s_value], MAXMAPVARIABLESTRING);

		if (!g_bChanged[iKeyIndex])
		{
			g_bChanged[iKeyIndex] = true;
			g_iChanged++;
		}

		return iKeyIndex;
	}

	if (g_iKeyCount < MAXMAPVARIABLES)
	{
		iKeyIndex = g_iKeyCount;
		float fValue = view_as<float>(GetNativeCell(2));
		FloatToString(fValue, g_sMapVariable[iKeyIndex][s_value], MAXMAPVARIABLESTRING);
		g_sMapVariable[iKeyIndex][s_key] = sKey;
		g_iId[iKeyIndex] = -1;
		g_bChanged[iKeyIndex] = true;
		g_iChanged++;
		g_smMapVariables.SetValue(sKey, iKeyIndex);
		g_iKeyCount++;
		return iKeyIndex;
	}

	return -1;
}

public void OnMapStart()
{
    //SaveMapVariables();	
    GetMapVariables();
}

public OnMapEnd()
{	
	// @TODO: Might require us to fire a forward other people can save their mapvariables during?
    SaveMapVariables();
	
	g_iMap = -1;
	g_smMapVariables.Clear();
	g_iKeyCount = 0;
	g_iChanged = 0;
}

void GetMapVariables()
{
	if (g_hDatabase == null || g_iServer == -1 || g_iMap != -1)
	{
		// We don't know what map and/or server this is yet OR we already got the map's variables
		return;
	}
	
	int iCurrentTime = GetTime();
	if ((iCurrentTime - g_iTime) < 5)
	{
		// OnMapStart was probably fired multiple times in quick succession
		return;
	}
	g_iTime = iCurrentTime;
	
	char sMap[64]; char sQuery[255];
	GetCurrentMap(sMap, sizeof(sMap));

	FormatEx(sQuery, sizeof(sQuery), "SELECT `id` FROM `maps` WHERE `server_id` = %d AND `map` = '%s'", g_iServer, sMap);		
	//FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, `key`, `value` FROM `mapvariables` WHERE `map_id` = %d", iMap);
	//"SELECT * FROM `maps` LEFT JOIN `mapvariables` ON `maps`.`id` = `mapvariables`.`map_id`"

	DataPack pack = CreateDataPack();
	pack.WriteString(sMap);

	g_hDatabase.Query(SQL_Callback_GetMap, sQuery, pack, DBPrio_Normal);
}

void SaveMapVariables()
{
    // StringMapSnapshot smsMapVariables = g_smMapVariables.Snapshot();
    // if (smsMapVariables.Length > 0)
    // {
    //      Transaction tx = SQL_CreateTransation();
    //      char sBuffer[MAXMAPVARIABLESTRING]; char sQuery[255];
    //      for (int i = 0; i < smsMapVariables.Length; i++)
    //      {
    //          smsMapVariables.GetKey(i, sBuffer, sizeof(sBuffer));
    //          g_smMapVariables.GetString(sBuffer, sBuffer, sizeof(sBuffer));
    //          // Update or insert?
    //      }
    // }
    if (g_iMap == -1 || g_iChanged == 0)
    {
        // No mapvariables changed
        return;
    }

    Transaction tx = SQL_CreateTransaction();
    char sQuery[255];
    for (int i = 0; i < g_iKeyCount; i++)
    {
        if (!g_bChanged[i])
        {
            continue;
        }

        if (g_iId[i] == -1)
        {
            FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `mapvariables` (`map_id`, `key`, `value`) VALUES (%d, '%s', '%s')", g_iMap, g_sMapVariable[i][s_key], g_sMapVariable[i][s_value]); // Key is reserved word in MySQL
        }
        else
        {
            FormatEx(sQuery, sizeof(sQuery), "UPDATE `mapvariables` SET `value` = '%s' WHERE `id` = %d", g_sMapVariable[i][s_value], g_iId[i]);
        }
        tx.AddQuery(sQuery);
    }

    g_hDatabase.Execute(tx, _, _, _, DBPrio_Low);
}

public void SQL_Callback_GetMapVariables(Database db, DBResultSet results, const char[] sError, any data)
{
	if (db == null || strlen(sError) != 0)
	{
		LogError("An error occured while fetching the mapvariables: %s", sError);
		return;
	}

	if (g_iMap != data)
	{
		// We're no longer on the same map
		return;
	}

	g_iKeyCount = 0;
	g_iChanged = 0;
	while (results.FetchRow())
	{
		g_iId[g_iKeyCount] = results.FetchInt(0);
		results.FetchString(1, g_sMapVariable[g_iKeyCount][s_key], MAXMAPVARIABLESTRING);
		results.FetchString(2, g_sMapVariable[g_iKeyCount][s_value], MAXMAPVARIABLESTRING);
		g_smMapVariables.SetValue(g_sMapVariable[g_iKeyCount][s_key], g_iKeyCount);
		g_bChanged[g_iKeyCount] = false;

		g_iKeyCount++;

		if (g_iKeyCount == MAXMAPVARIABLES)
		{
			//g_iKeyCount--;
			LogError("Getting more mapvariables from the map than we can save in the internal array, consider making MAXMAPVARIABLES higher");
			break;
		}
	}

	Call_StartForward(g_hMapVariablesFetched);
	Call_Finish();
}

public void SQL_Callback_GetMap(Database db, DBResultSet results, const char[] sError, any data)
{
	if (db == null || strlen(sError) != 0)
	{
		LogError("An error occured while fetching the map: %s", sError);
		return;
	}

	char sOldMap[64]; char sCurrentMap[64];
	
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	pack.ReadString(sOldMap, sizeof(sOldMap));
	delete pack;
	
	GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));

	if (!StrEqual(sOldMap, sCurrentMap))
	{
		// We're already on the next map
		LogMessage("Only got the current map while on the next one");
		return;
	}

	if (results.FetchRow())
	{
		g_iMap = results.FetchInt(0);

		char sQuery[255];
		FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, `key`, `value` FROM `mapvariables` WHERE `map_id` = %d", g_iMap); // key is a reserved variable in MySQL

		g_hDatabase.Query(SQL_Callback_GetMapVariables, sQuery, g_iMap, DBPrio_Normal);
	}
	else
	{
		char sQuery[255];
		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `maps` (`map`, `server_id`) VALUES ('%s', %d)", sCurrentMap, g_iServer);

		g_hDatabase.Query(SQL_Callback_SaveMap, sQuery, _, DBPrio_Normal);
	}

	Call_StartForward(g_hMapVariablesFetched);
	Call_Finish();
}

public void SQL_Callback_SaveMap(Database db, DBResultSet results, const char[] sError, any data)
{
	if (db == null || strlen(sError) != 0)
	{
		LogError("An error occured while saving the map: %s", sError);
	}
	
	g_iMap = results.InsertId;
}

/***************************************** CORE FORWARDS ******************************************/
public void Core_OnConnectionEstablished()
{
    g_hDatabase = Core_GetDatabase();
    GetMapVariables();
}

public void Core_OnServerConnected(int iServer)
{
	g_iServer = iServer;
	GetMapVariables();
}