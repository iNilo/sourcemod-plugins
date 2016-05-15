#include <sourcemod>
#include <cstrike>
//#include <emitsoundany>
#include <cnf_core>
#include <warden>

#pragma newdecls required
#pragma semicolon 1

int g_iWarden = -1;

bool g_bRoundStartQueue = false;

ArrayList g_aWardenQueue = null;
//ArrayList g_aPreviousWarden = null;

Handle g_hPickWardenTimer = null;

// ConVars
ConVar g_hWardenPickTime = null;

// Forwards
Handle g_hOnWardenClaimed = null;
Handle g_hOnTryingToBecomeWarden = null;

public void OnPluginStart()
{
	g_aWardenQueue = new ArrayList();
	//g_aPreviousWarden = new ArrayList();
	
	RegisterConvars();
	RegisterConsoleCmds();
	RegisterForwards();
	HookEvents();
}

void RegisterForwards()
{
	g_hOnWardenClaimed = CreateGlobalForward("OnWardenClaimed", ET_Ignore, Param_Cell);
	g_hOnTryingToBecomeWarden = CreateGlobalForward("OnTryingToBecomeWarden", ET_Event, Param_Cell);
}

public void OnMapStart()
{
	//PrecacheSoundAny
	//AddFileToDownloadstable
}

void SetWarden(int client)
{
	g_iWarden = client;
	// Play sound
	PrintToChatAll(" \x0C[WARDEN] \x01%N has become the new warden!");
	
	// Notify other plugins about our new warden
	Call_StartForward(g_hOnWardenClaimed);
	Call_PushCell(client);
	Call_Finish();
}

void RemoveWarden()
{
    g_iWarden = -1;
    // Play sound
}

public Action OnClientCommandKeyValues(int client, KeyValues kv) 
{ 
    char sCmd[64]; 
     
    if (kv.GetSectionName(sCmd, sizeof(sCmd)) && StrEqual(sCmd, "ClanTagChanged", false)) 
    {
        // Might have to watch out we don't get into an infinte loop changing clantags here
        SetClanTag(client);
        return Plugin_Handled;
    } 
     
    return Plugin_Continue; 
}

void SetClanTag(int client)
{
	char tag[32];
	if (IsWarden(client)) {
		tag = "[Warden]";
	}
	// When we add T Warden, we can also add that here
	
	CS_SetClientClanTag(client, tag);
}

/********************************* COMMANDS ***********************************/
void RegisterConsoleCmds()
{
    RegConsoleCmd("sm_warden", Command_ClaimWarden);
    RegConsoleCmd("sm_w", Command_ClaimWarden);
    RegConsoleCmd("sm_uw", Command_Unwarden);
    RegConsoleCmd("sm_unwarden", Command_Unwarden);
    
    RegAdminCmd("sm_rw", Command_RemoveWarden, ADMFLAG_SLAY);
    RegAdminCmd("sm_removewarden", Command_RemoveWarden, ADMFLAG_SLAY);
    
    //RegConsoleCmd("mark", Command_ShowMarker);
}

public Action Command_ClaimWarden(int client, int args)
{
	if (g_iWarden != -1)
	{
		ReplyToCommand(client, "The current warden is %N", g_iWarden);
		return Plugin_Handled;
	}
	
	if (GetClientTeam(client) != CS_TEAM_CT)
	{
		ReplyToCommand(client, "There is currently no warden!");
		return Plugin_Handled;
	}
	
	// Let other people know someone is trying to become warden so they can block it or fire other actions
	Action result = Plugin_Continue;
	Call_StartForward(g_hOnTryingToBecomeWarden);
	Call_PushCell(client);
	Call_Finish(result);
	
	if (result > Plugin_Continue)
	{
		// A plugin blocked this player from becoming warden
		return Plugin_Handled;
	}

	if (!g_bRoundStartQueue)
	{
		SetWarden(client);
		return Plugin_Handled;
	}
	
	int iUserId = GetClientUserId(client);
	if (g_aWardenQueue.FindValue(iUserId) != -1)
	{
		ReplyToCommand(client, "You and %d other guards are currently preparing to become warden.", g_aWardenQueue.Length - 1);
		return Plugin_Handled;
	}
	
	// Add to people trying to claim
	g_aWardenQueue.Push(client);

	return Plugin_Handled;
}

public Action Command_Unwarden(int client, int args)
{
	if (IsWarden(client)) {
		RemoveWarden();
	}
	
	return Plugin_Handled;
}

public Action Command_RemoveWarden(int client, int args)
{
	if (g_iWarden == -1)
	{
		ReplyToCommand(client, "We don't currently have a warden!");
		return Plugin_Handled;
	}
	
	RemoveWarden();
	ShowActivity2(client, "[Warden]", "Removed the active warden");
	
	return Plugin_Handled;
}

bool IsWarden(int client)
{
    return g_iWarden == client;
}

/********************************** EVENTS *******************************/
void HookEvents()
{
    HookEvent("player_team", Event_LeavingActiveTeam);  // This also gets called when leaving the game
    HookEvent("player_death", Event_LeavingActiveTeam);
    HookEvent("round_start", Event_RoundStart);
    //HookEvent("round_end", Event_RoundEnd);
}

public Action Event_LeavingActiveTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (client == -1)
	{
		// We have no idea who this is, make sure this wasn't our warden!
		if (g_iWarden != -1 && !IsClientInGame(g_iWarden))
		{
			RemoveWarden();
		}
		
		return Plugin_Continue;
	}
	
	// If the player is currently warden, he should no longer be it
	if (IsWarden(client))
	{
		RemoveWarden();
		return Plugin_Continue;
	}
	
	// Remove the player from the warden queue if he is in it
	int iUserId = GetClientUserId(client);
	int iQueuePos = g_aWardenQueue.FindValue(iUserId);
	if (iQueuePos != -1)
	{
		g_aWardenQueue.Erase(iQueuePos);
	}
	
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_iWarden = -1;
	g_bRoundStartQueue = true;
	
	g_hPickWardenTimer = CreateTimer(g_hWardenPickTime.FloatValue, Timer_PickWarden, TIMER_FLAG_NO_MAPCHANGE);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			// Make sure everyone has their clan tag reset
			SetClanTag(i);
		}
	}
}

public Action Timer_PickWarden(Handle timer)
{
	if (timer != g_hPickWardenTimer)
	{
		// This is a timer from another round?
		return Plugin_Stop;
	}
	
	g_bRoundStartQueue = false;
	
	int iWardenCandidates = g_aWardenQueue.Length;
	if (iWardenCandidates > 0)
	{
		int iRandomWardenPos = GetRandomInt(0, g_aWardenQueue.Length - 1);
		int iWardenCandidate = GetClientOfUserId(g_aWardenQueue.Get(iRandomWardenPos));
		
		if (iWardenCandidate == -1)
		{
			LogError("For some reason we have a warden candidate with client id -1 in our PickWarden timer callback. This isn't supposed to be possible.");
		}
		
		SetWarden(iWardenCandidate);
		
		g_aWardenQueue.Clear();
		
		return Plugin_Stop;
	}
	
	// There were no candidates, prepare to choose one randomly
	int iCTCount = GetTeamAliveClientCount(CS_TEAM_CT);
	
	if (iCTCount == 0)
	{
		// There are no CT's
		return Plugin_Stop;
	}
	
	// Choose a random CT and make him warden
	int iRandomCTPos = GetRandomInt(0, iCTCount - 1);
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == CS_TEAM_CT)
		{			
			if (count == iRandomCTPos)
			{
				SetWarden(i);
				break;
			}
			
			count++;
		}
	}
	
	return Plugin_Stop;
}


/******************************** NATIVES ********************************/
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Warden_IsWarden", Native_IsWarden);
	CreateNative("Warden_Set", Native_SetWarden);
	CreateNative("Warden_Remove", Native_RemoveWarden);
	CreateNative("Warden_GetWarden", Native_GetWarden);
	CreateNative("Warden_Exists", Native_WardenExists);
	
	return APLRes_Success;
}

public int Native_IsWarden(Handle plugin, int args)
{
    int client = GetNativeCell(1);
    return view_as<int>(IsWarden(client));
}

public int Native_SetWarden(Handle plugin, int args)
{
    int client = GetNativeCell(1);
    SetWarden(client);
}

public int Native_RemoveWarden(Handle plugin, int args)
{
    RemoveWarden();
}

public int Native_GetWarden(Handle plugin, int args)
{
    return g_iWarden;
}

public int Native_WardenExists(Handle plugin, int args)
{
    return view_as<int>(g_iWarden != -1);
}

/******************************** CONVARS ********************************/
void RegisterConvars()
{
	g_hWardenPickTime = CreateConVar("warden_picktime", "5.0", "Time (starting from round start) during which guards are able to become warden candidates", FCVAR_NONE, true, 0.0, false);
}