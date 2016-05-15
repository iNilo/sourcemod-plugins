#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <meitisstocks>
#include <mapvariables>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_CONFIG MEITIS_CONFIG ... "maps.cfg"

// func breakable flags
#define ONLY_BREAK_ON_TRIGGER 1

// func door flags
#define DOOR_STARTS_OPEN			1
#define DOOR_NON_SOLID_TO_PLAYER	4
#define DOOR_PASSABLE				8
#define DOOR_USE_OPENS				256
#define DOOR_TOUCH_OPENS			1024

// @TODO: check if player can horizontally fit through door (m_vecMin, m_vecMax)
// @TODO: activate button
// @TODO: cell button will be activated within first 2 minutes of first round


// @TODO: entoutputinfo : https://forums.alliedmods.net/showthread.php?p=2275379


// if has name
// if can horizontally fit standing player
// if has clients in range
// if is pressed during first 2 minutes of first round
// if linked to button
// if breakable don't forget to check health > x / initially locked

char g_sCelldoors[20][MAX_NAME_LENGTH];
int g_iCelldoors;
int g_iCellButton = -1;
int g_CellButtonHammerId = -1;

bool g_bEstimatedCelldoors;
bool g_bGotCelldoorEntities;
bool g_bIsButton;
bool g_bFetchedMapVariables;

int g_iButtonPressed[MAXPLAYERS+1] = { -1, ... };
int g_iLatestButtonPress = -1;

StringMap g_sDoors = null;

#define MAXDOORS    64

int g_iDoorCount;

enum DoorInfoInt
{
    i_count,
    i_score,
	i_uniqueprisoners
}

char g_sDoorNames[MAXDOORS][MAX_NAME_LENGTH];
int g_iDoorInfo[MAXDOORS][DoorInfoInt];
bool g_bPlayersNearDoor[MAXDOORS][MAXPLAYERS+1];


char g_sButtonEntities[][] = {
    "func_button",
    "func_rot_button",
    "momentary_rot_button"
};

char g_sDoorEntities[][] = { 
    "func_door",
    "func_door_rotating",
    "momentary_door",
    "prop_door_rotating",
    "func_movelinear"
};	// Possible also func_wall_toggle?

public Plugin myinfo =
{
	name = "Doorcontrol",
	author = "Meitis",
	version = "0.1",
	description = "Controls buttons and doors on the map",
	url = ""
};

public void OnPluginStart()
{
	g_sDoors = new StringMap();
	
	RegConsoleCmd("sm_celldoors", Command_GetCelldoorEstimations);
	
	RegAdminCmd("sm_setcellbutton", Command_SetCellButton, ADMFLAG_BAN);
	
    for (int i = 0; i < sizeof(g_sButtonEntities); i++)
    {
        HookEntityOutput(g_sButtonEntities[i], "OnPressed", OnButtonActivated);
    }

	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnMapStart()
{
    g_bFetchedMapVariables = false;
    g_bGotCelldoorEntities = false;
	g_bEstimatedCelldoors = false;
}

public void OnButtonActivated(const char[] output, int caller, int activator, float delay)
{
	if(activator > 0 && activator <= MaxClients) // Is valid client index 
    {
    	char sButtonName[MAX_NAME_LENGTH];
    	GetEntPropString(caller, Prop_Data, "m_iName", sButtonName, sizeof(sButtonName));
        PrintToAdminConsole("%N activated button %s (caller: %d, delay: %f)", activator, sButtonName, caller, delay);
        
        g_iButtonPressed[activator] = caller;
    }
    g_iLatestButtonPress = caller;
}

public void OnDoorOpen(const char[] output, int caller, int activator, float delay)
{
    // activator is door?
    // source: https://github.com/raziEiL/My_plugins/blob/master/TheDoors.sp
	
	char sCallerName[MAX_NAME_LENGTH]; char sActivatorName[MAX_NAME_LENGTH];
	Entity_GetName(caller, sCallerName, sizeof(sCallerName));
	Entity_GetName(activator, sActivatorName, sizeof(sActivatorName));
    
    // I believe caller is the door, activator is the button (not sure though)
    // according to https://forums.alliedmods.net/showthread.php?t=125113 activator is the person that pressed/shot the button
	PrintToChatAll("OnDoorOpen: caller %d (%s), activator %d (%s). Delay: %f", caller, sCallerName, activator, sActivatorName, delay);
}

// Source: https://github.com/Kailo97/smartjaildoors/blob/master/addons/sourcemod/scripting/smartjaildoors.sp
float DistanceBetweenPoints(const float point1[3], const float point2[3])
{
	return SquareRoot(Pow(point2[0] - point1[0], 2.0) + Pow(point2[1] - point1[1], 2.0) + Pow(point2[2] - point1[2], 2.0));
}

// @TODO OnEntityCreated check if door cell and check if it's closed already
// public OnEntityCreated(entity, const String:classname[])
//{
//	if(StrEqual(classname, "prop_door_rotating_checkpoint"))
//	{		
//		if(GetEntProp(entity, Prop_Send, "m_eDoorState") == 0)
//		{
//			HookSingleEntityOutput(entity, "OnFullyOpen", OnStartSFDoorFullyOpened, true);
//		}
//	}
//}

public void OnMapVariablesFetched()
{
    g_bFetchedMapVariables = true;

	int iIsCellbutton = GetMapVariableInt("is_cellbutton");
	
	if (iIsCellbutton < 0)
	{
		// We haven't saved any celldoor information yet
		ResetDoorEstimations();
		return;
	}
	
	if (iIsCellbutton == 1)
	{
		// This is a cellbutton
		g_bIsButton = true;
		g_iCellButtonHammerId = GetMapVariableInt("celldoors");
		GetCellButtonEntity();
		
		return;
	}
	
    char sBuffer[255];
    if (GetMapVariableString("celldoors", sBuffer, sizeof(sBuffer)) != NO_MAPVARIABLE_AVAILABLE)
    {
		g_bIsButton = false;
        g_iCelldoors = ExplodeString(sBuffer, ";", g_sCelldoors, sizeof(g_sCelldoors), sizeof(g_sCelldoors[]));
		g_bGotCelldoorEntities = true;
		

        OpenCellsWarmup();
    }
}

bool OpenCellsWarmup()
{
    // Detect if it's warmup
    // credits: https://forums.alliedmods.net/showpost.php?p=1974884&postcount=2
    if(GameRules_GetProp("m_bWarmupPeriod") == 1) 
    {
        return OpenCells();
    }
    return false;
}

bool OpenCells()
{
	if (!g_bGotCelldoorEntities)
	{
		return false;
	}
	
	if (g_bIsButton)
	{
		// It's the cellbutton
		AcceptEntityInput(g_iCellButton, "Use");
		return true;
	}

	int iMaxEntities = GetMaxEntities();
	for (int iEnt = MaxClients + 1; iEnt < iMaxEntities; iEnt++)
	{
		if (!IsValidEntity(iEnt))
		{
			continue;
		}

		char sName[MAX_NAME_LENGTH];
		Entity_GetName(iEnt, sName, sizeof(sName));
		for (int i = 0; i < g_iCelldoors; i++)
		{
			if (StrEqual(sName, g_sCelldoors[i], true))
			{
				OpenCell(iEnt);
				break;
			}
		}
	}
	
	return true;
}

void OpenCell(int iEnt)
{
    char sClass[MAX_NAME_LENGTH];
    GetEntityClassname(iEnt, sClass, sizeof(sClass));
            
    if (StrEqual(sClass, "func_breakable"))
    {
        AcceptEntityInput(iEnt, "Break");
    }
    else
    {
        AcceptEntityInput(iEnt, "Open");
    }
}

void DetermineCelldoors()
{
    if (!g_bFetchedMapVariables || g_bGotCelldoorEntities || g_bEstimatedCelldoors || GameRules_GetProp("m_bWarmupPeriod") == 1)
    {
        return;
    }

    // @TODO: block if there are less than x T's?
	g_bEstimatedCelldoors = true;
    
    // Determine what the doors are
    int iMaxEntities = GetMaxEntities();
    for (int iEnt = MaxClients + 1; iEnt < iMaxEntities; iEnt++)
    {
        if (!IsValidEntity(iEnt))
        {
            continue;
        }

        CheckIfPossibleCelldoor(iEnt);
    }
    
    g_tDetermineCelldoorsTimer = CreateTimer(120.0, Timer_DetermineCelldoors);
}

void CheckIfPossibleCelldoor(int iEnt)
{	
	char sClassname[32];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname));

	// @TODO: what's faster here? stringmap or looping through door entities?
	for (int i = 0; i < sizeof(g_sDoorEntities); i++)
	{
		if (!StrEqual(g_sDoorEntities[i], sClassname))
		{
			continue;
		}
				
		char sName[MAX_NAME_LENGTH];
		if (!Entity_GetName(iEnt, sName, sizeof(sName)))
		{
			// This has no name so can't be a celldoor
			break;
		}
		
		if (StrContains(sName, "secret", false) != -1)
		{
			// Secrets are defo not celldoors
			break;
		}
		
		if (StrEqual(sClassname, "func_breakable"))
		{
			int iFlags = GetEntProp(iEnt, Prop_Data, "m_spawnflags");
			if (!(iFlags & ONLY_BREAK_ON_TRIGGER))	// https://developer.valvesoftware.com/wiki/Func_breakable
			{
				// If it's breakable normally it's defo not a celldoor
				break;
			}
		}
		else if (StrEqual(sClassname, "func_door") || StrEqual(sClassname, "func_door_rotation") || StrEqual(sClassname, "prop_door_rotating"))
		{
			int iFlags = GetEntProp(iEnt, Prop_Data, "m_spawnflags");
			if (iFlags & (DOOR_STARTS_OPEN | DOOR_NON_SOLID_TO_PLAYER | DOOR_PASSABLE | DOOR_USE_OPENS | DOOR_TOUCH_OPENS))
			{
				// This door doesn't open like a celldoor
				break;
			}
			
			int iSpawnPosition = GetEntProp(iEnt, Prop_Data, "m_eSpawnPosition");
			if (iSpawnPosition == 1)
			{
				// Door starts open
				break;
			}
		}
		
		float vMin[3]; float vMax[3];
		GetEntPropVector(iEnt, Prop_Send, "m_vecMins", vMin);
		GetEntPropVector(iEnt, Prop_Send, "m_vecMaxs", vMax);
		
		if ((vMax[2] - vMin[2]) < 64.0 && !StrEqual(sClassname, "func_movelinear"))
		{
			// Player can't fit through this height-wise without crouching and it's not an elevator
			break;
		}
		
		float flPosition[3];
		GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", flPosition);
		
		int clients[MAXPLAYERS+1]; int iDoorPos;
		int iClientCount = GetPlayersInRange(clients, sizeof(clients), flPosition, 600.0, CS_TEAM_T);
		
		// Has a door with this name been registered yet?
		if (!g_sDoors.GetValue(sName, iDoorPos))
		{
			iDoorPos = g_iDoorCount;
			g_sDoors.SetValue(sName, iDoorPos);
			g_sDoorNames[iDoorPos] = sName;
			
			if (StrContains(sName, "cell", false) != -1 || StrContains(sName, "jail", false) != -1)
			{
				g_iDoorInfo[iDoorPos][i_score]++;
			}
			
			g_iDoorCount++;
		}
		
		g_iDoorInfo[iDoorPos][i_count]++;
		g_iDoorInfo[iDoorPos][i_score] += iClientCount;
		
		for (int j = 0; j < iClientCount; j++)
		{
			if (!g_bPlayersNearDoor[iDoorPos][clients[j]])
			{
				g_iDoorInfo[iDoorPos][i_uniqueprisoners]++;
				g_bPlayersNearDoor[iDoorPos][clients[j]] = true;
			}
		}
		
        if (StrEqual(sName, "func_breakable"))
		{
			HookSingleEntityOutput(iEnt, "OnBreak", OnDoorOpen, false);
		}
		else
		{
			HookSingleEntityOutput(iEnt, "OnOpen", OnDoorOpen, false);
		}
		
		break;
	}
}

void SaveCellButton(int iEnt)
{
	int iHammerID = GetEntProp(iEnt, Prop_Data, "m_iHammerID");
	
	g_iCellButtonHammerId = iHammerID;
	g_iCellButton = EntIndexToEntRef(iEnt);
	g_bGotCelldoorEntities = true;
	
	SetMapVariableInt("is_cellbutton", 1);
	SetMapVariableInt("celldoors", iHammerID);
}

void GetCellButtonEntity()
{
	for (int i = 0; i < sizeof(g_sButtonEntities); i++)
	{
		int iEnt = -1;
		while ((iEnt = FindEntityByClassname(iEnt, g_sButtonEntities[i])) != -1)
		{
			int iHammerID = GetEntProp(iEnt, Prop_Data, "m_iHammerID");
			if (iHammerID == g_CellButtonHammerId)
			{
				g_iCellButton = EntIndexToEntRef(iEnt);
				return;
			}
		}
	}
}

void ResetDoorEstimations()
{
	// Reset door estimations
	for (int i = 0; i < g_iDoorCount; i++)
	{
		g_iDoorInfo[i][i_score] = 0;
		g_iDoorInfo[i][i_count] = 0;
		g_iDoorInfo[i][i_uniqueprisoners] = 0;
		
		for (int j = 1; j <= MaxClients; j++)
		{
			g_bPlayersNearDoor[i][j] = false;
		}
	}
	
	g_iDoorCount = 0;
	g_sDoors.Clear();
}

public Action Command_GetCelldoorEstimations(int client, int args)
{
	for (int i = 0; i < g_iDoorCount; i++)
	{
		PrintToChatAll("%s: %d (%d doors, %d prisoners)", g_sDoorNames[i], g_iDoorInfo[i][i_score], g_iDoorInfo[i][i_count], g_iDoorInfo[i][i_uniqueprisoners]);
	}
}

public Action Command_SetCellButton(int client, int args)
{
	int iEnt = GetClientAimTarget(client, false);
	if (iEnt < 0)
	{
		ReplyToCommand(client, "Button not found");
		return Plugin_Handled;
	}
	
	char sClassname[MAX_NAME_LENGTH];
	GetEntityClassname(iEnt, sClassname, sizeof(sClassname));
		
	for (int i = 0; i < sizeof(g_sButtonEntities); i++)
	{
		if (StrEqual(sClassname, g_sButtonEntities[i]))
		{
			SaveCellButton(iEnt);
			ReplyToCommand(client, "Successfully added cellbutton");
			
			return Plugin_Handled;
		}
	}
	
	// This is not a button
	ReplyToCommand(client, "This entity is not a cellbutton");
	return Plugin_Handled;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    DetermineCelldoors();
    
    if (g_bFetchedMapVariables && g_bGotCelldoorEntities && g_bIsButton && (g_iCellButton == -1 || EntRefToEntIndex(g_iCellButton) == INVALID_ENT_REFERENCE))
    {
        // Not sure if this needs to be redone every time, but w/e
        // @TODO: check if this has to be regotten every time
        g_iCellButton = -1;
        GetCellButtonEntity();
    }

    OpenCellsWarmup();
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if(GameRules_GetProp("m_bWarmupPeriod") == 1 && g_bGotCelldoorEntities) 
    {
		int client = GetClientOfUserId(event.GetInt("userid"));
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 2.2);
		SetEntityGravity(client, 0.4);
		SetEntProp(client, Prop_Send, "m_iHealth", 9999);
	}
}

/*************** SMLIB EXCERPT ***************/

/**
 * Gets the Name of an entity.
 *
 * @param entity			Entity index.
 * @param buffer			Return/Output buffer.
 * @param size				Max size of buffer.
 * @return					Number of non-null bytes written.
 */
stock int Entity_GetName(int entity, char[] buffer, int size)
{
	return GetEntPropString(entity, Prop_Data, "m_iName", buffer, size);
}

stock int GetPlayersInRange(int[] buffer, int maxBuffer, float coords[3], float range, int filter = CS_TEAM_NONE)
{
    int iPlayerCount = 0;
    
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || !IsPlayerAlive(client) || !(filter == CS_TEAM_NONE || filter == GetClientTeam(client)) || iPlayerCount == maxBuffer)
        {
            continue;
        }
        
        float flPosition[3];
        GetClientAbsOrigin(client, flPosition);
        
        if (GetVectorDistance(coords, flPosition) <= range)
        {
            buffer[iPlayerCount] = client;
            iPlayerCount++;
        }
    }
    
    return iPlayerCount;
}