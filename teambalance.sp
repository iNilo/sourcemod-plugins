#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <ctban>
#include <meitisstocks>
#include <mapvariables>
#include <teambalance>
#include <lastrequest>

// @TODO: move all IsCTBanned checks and the <ctban> out of here, that doesn't belong here imo. CT joins could be blocked in ctban plugin using teambalancer forwards
// @TODO: use OnCTBanned forward to remove from guard queue?
// @TODO: consider switching ArrayList to arrays with MAXPLAYERS size + length variable for performance? (probably not worth it)

public Plugin myinfo =
{
	name = "Jailbreak Teambalancer",
	author = "Meitis",
	description = "This plugin makes sure the team ratio is properly kept",
	version = "0.2",
	url = ""
}

enum EJoinTeamReason
{
	k_OneTeamChange=0,
	k_TeamsFull=1,
	k_TTeamFull=2,
	k_CTTeamFull=3,
	k_CannotBeSpectator=4,
	k_HumansJoinTeamT=5,
	k_HumansJoinTeamCT=6,
	k_TooManyTerrorists=7,
	k_TooManyCTs=8
}

bool g_bJoinedWillingly[MAXPLAYERS+1];
bool g_bNeedsInitialTeam[MAXPLAYERS+1] = { true, ...};
bool g_bLastRequestStarted;

char g_sMap[64];

int g_iTSpawnCount = -1;
int g_iCTSpawnCount = -1;
//int g_iSelectedTeam[MAXPLAYERS+1];

float g_flTeamRatio =  3.0;
ArrayList g_aCTList = null;
ArrayList g_aGuardQueue = null;

Handle g_hJoinGuardAttempt = null;

ConVar g_cDefaultRatio = null;
ConVar g_cMaxRatio = null;
ConVar g_cMinRatio = null;
ConVar g_cExpandRate = null;
ConVar g_cContractRate = null;

public void OnPluginStart()
{
	g_aCTList = new ArrayList();
	g_aGuardQueue = new ArrayList();

	CreateConfig();
	RegisterCommands();    
	HookEvents();

	g_hJoinGuardAttempt = CreateGlobalForward("Teambalance_OnGuardJoinAttempt", ET_Event, Param_Cell);
}

void CreateConfig()
{
	g_cDefaultRatio = CreateConVar("sm_teambalance_ratio", "3.0", "Set the default ratio on map start for the teambalancing");
	g_cMaxRatio = CreateConVar("sm_teambalance_maxratio", "4.5", "The maximum ratio that can be reached by the dynamic teamratio calculation");
	g_cMinRatio = CreateConVar("sm_teambalance_minratio", "2.0", "The minimum ratio that can be reached by the dynamic teamratio calculation");
	g_cExpandRate = CreateConVar("sm_teambalance_expandratio", "0.15", "The rate at which the ratio can expand");
	g_cContractRate = CreateConVar("sm_teambalance_contractratio", "0.25", "The rate at which the ratio can contract");

	AutoExecConfig();
}

public void OnMapStart()
{
	// As long as we haven't gotten the dynamic teamratio from the database yet, set it on a default
	g_flTeamRatio = g_cDefaultRatio.FloatValue;

	g_aGuardQueue.Clear();
	g_aCTList.Clear();

	g_iTSpawnCount = -1;
	g_iCTSpawnCount = -1;

	GetCurrentMap(g_sMap, sizeof(g_sMap));

	// Give plugins a chance to create new spawns
	CreateTimer(0.1, Timer_OnMapStart);
}

public void OnMapEnd()
{
	SetMapVariableFloat("teamratio", g_flTeamRatio);
}

public void OnClientPutInServer(int client)
{	
	g_bNeedsInitialTeam[client] = true;
	g_bJoinedWillingly[client] = true;

	// Just to be sure if any of the logic messes up we don't fuck things up completely
	//g_iSelectedTeam[client] = CS_TEAM_T;
}

public Action Timer_OnMapStart(Handle timer) // Passing any data as argument here is not required
{
	g_iTSpawnCount = 0;
	g_iCTSpawnCount = 0;

	int iEnt = -1;
	while((iEnt = FindEntityByClassname(iEnt, "info_player_counterterrorist")) != -1) ++g_iCTSpawnCount;
	iEnt = -1;
	while((iEnt = FindEntityByClassname(iEnt, "info_player_terrorist")) != -1) ++g_iTSpawnCount;

	return Plugin_Stop;
}

public void OnMapVariablesFetched()
{
	//LogMessage("Starting map with %f before getting mapvariables", g_flTeamRatio);
	GetMapVariableFloat("teamratio", g_flTeamRatio);
	//LogMessage("Starting map with %f after getting mapvariables", g_flTeamRatio);
}

Action AddGuard(int client)
{
	int iUserId = GetClientUserId(client);
	int iQueuePosition = g_aGuardQueue.FindValue(iUserId);
	int iTargetTeamPlayerCount = GetTeamClientCount(CS_TEAM_CT);
	int iCurrentTeam = GetClientTeam(client);

	if (iCurrentTeam == CS_TEAM_CT)
	{
		// You are CT already, why would you still need to be changed to it
		PrintToChat(client, "You are CT already, why would you need us to change you to it silly?");
		return Plugin_Handled;
	}

	/*if (IsCTBanned(client)) // @TODO: Might be useful to move this to the JoinGuardAttempt forward so we have all ctban logic in one plugin
	{
		PrintHintText(client, "You are currently ctbanned and thus can't join CT");
		return Plugin_Handled;
	}*/

	Action canJoin = JoinGuardAttempt(client); // Let other plugins know someone is trying to join CT and handle if necessary
	if (canJoin != Plugin_Continue)
	{
		if (iCurrentTeam == CS_TEAM_NONE)
		{
			// Make sure the player at the very least has an initial team
			CS_SwitchTeam(client, CS_TEAM_T);
			
			if (GetTeamClientCount(CS_TEAM_T) == 1)
			{
				CS_RespawnPlayer(client);
			}
		}
		return canJoin;
	}

	if (iTargetTeamPlayerCount == 0)
	{
		// Let the first CT join freely so we can start playing, but remove him from the queue first if he's in it
        // These are normally taken care of in the Event_PlayerTeam logic
		//if (iQueuePosition != -1)
		//{
		//	g_aGuardQueue.Erase(iQueuePosition);
		//}
		//g_aCTList.Push(iUserId);
		g_bJoinedWillingly[client] = true;


		return Plugin_Continue;
	}
	else
	{
		if (iQueuePosition == -1)
		{        
			g_aGuardQueue.Push(iUserId);
			PrintToChat(client, "You have been added to the guard queue! There are %d players in the queue in total.", g_aGuardQueue.Length);
		}
		else
		{
			PrintToChat(client, "You are already waiting in the guard queue! There are %d players in the queue in total.", g_aGuardQueue.Length);
		}
		return Plugin_Handled;
	}
}

void RemoveFromGuardQueue(int client)
{
    int iUserId = GetClientUserId(client);
    int iQueuePosition = g_aGuardQueue.FindValue(iUserId);
    
    if (iQueuePosition != -1)
    {
        // This person is in the guard queue
        g_aGuardQueue.Erase(iQueuePosition);
    }
}

int SwapNextGuard()
{
	if (g_aGuardQueue.Length == 0)
	{
		return -1;
	}

	int iPos = GetRandomInt(0, g_aGuardQueue.Length - 1);
	int iClient = GetClientOfUserId(g_aGuardQueue.Get(iPos));

	g_aGuardQueue.Erase(iPos);

	if (iClient == 0)
	{
		LogError("[TB] Next guard is client 0!");
	}

	g_bJoinedWillingly[iClient] = true;    
	CS_SwitchTeam(iClient, CS_TEAM_CT);

	return iClient;
}

Action JoinGuardAttempt(client)
{
	Action result = Plugin_Continue;

	// Let other plugins know this prisoner is trying to join guard
	Call_StartForward(g_hJoinGuardAttempt);
	Call_PushCell(client);
	Call_Finish(result);

	return result;
}

void SwapOnRoundEnd(int client, int iTeam)
{
	SetEntProp(client, Prop_Send, "m_iPendingTeamNum", iTeam);     // @TODO: Check if correct way to call this?
}

public void OnClientDisconnect(int client)
{
	int iUserId = GetClientUserId(client);
	int iPos;
	
	if ((iPos = g_aGuardQueue.FindValue(iUserId)) != -1)
	{
		g_aGuardQueue.Erase(iPos);
	}

	if ((iPos = g_aCTList.FindValue(iUserId)) != -1)
	{
		g_aCTList.Erase(iPos);
	}
}

public void OnStartLR(int iPrisonerIndex, int iGuardIndex, int iLRType)
{
	g_bLastRequestStarted = true;
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

/************************ COMMANDS *************************/
void RegisterCommands()
{
	RegConsoleCmd("sm_guard", Command_Guard);
	RegConsoleCmd("sm_unguard", Command_Unguard);
	RegConsoleCmd("sm_swapme", Command_SwapMe); // For some LR nubs that don't understand how to get back on CT off of their own server

	//AddCommandListener(Command_JoinTeam, "autoteam"); // Doesn't seem to get fired on CS:GO
	AddCommandListener(Command_JoinTeam, "jointeam");
}

public Action Command_Guard(int client, int args)
{
	if (AddGuard(client) == Plugin_Continue)
	{
        // @TODO: clean up this logic! This gets fired when the player is allowed to join CT while skipping the queue
		CS_SwitchTeam(client, CS_TEAM_CT);
        
        
        /*int iCTCount = GetTeamClientCount(CS_TEAM_CT);
        if (iCTCount == 0)
        {*/
		CS_TerminateRound(0.0, CSRoundEnd_GameStart);
        //}
        
		CS_RespawnPlayer(client);
	}
	return Plugin_Handled;
}

public Action Command_Unguard(int client, int args)
{
    if (GetClientTeam(client) == CS_TEAM_CT)
    {
		SwapOnRoundEnd(client, CS_TEAM_T);
		ReplyToCommand(client, "You will be switched to the other team on round end so you don't miss the current round.");
		return Plugin_Handled;
    }
    
    RemoveFromGuardQueue(client);
    
    return Plugin_Handled;
}

public Action Command_SwapMe(int client, int args)
{
	if (GetClientTeam(client) != CS_TEAM_CT)
	{
		ReplyToCommand(client, "You don't need to be switched to the prisoner team");
		return Plugin_Handled;
	}
	
	SwapOnRoundEnd(client, CS_TEAM_T);
	ReplyToCommand(client, "You will be swapped to the prisoner team on round end");
	
	return Plugin_Handled;
}

public Action Command_JoinTeam(int client, const char[] command, int args)
{
	if (args < 1)
	{
		// Player didn't say what team they wanted to join, so let the normal jointeam information be returned
		return Plugin_Continue;
	}

	// We can't do GetClientTeam of client -1 and we can't set their teamnum either, how do we solve this?

	char sTeam[2];
	GetCmdArg(1, sTeam, sizeof(sTeam));
	int iTargetTeam = StringToInt(sTeam);

	if (!IsValidClient(client))
	{
		if (iTargetTeam == CS_TEAM_CT || iTargetTeam == CS_TEAM_NONE)
		{
			// Let's hope in the Event_PlayerTeam they'll have a proper client ID already since then they shouldn't be able to join CT manually anyways, but notify admins to be sure
			PrintToAdminChat("One of the players was possibly able to manually join CT when they shouldn't.");
		}
		
		return Plugin_Continue;
	}

	int iCurrentTeam = GetClientTeam(client);

	if (iTargetTeam == CS_TEAM_NONE)
	{
		/*PrintToChatAll("Target team NONE, switching to T");
		// Manually clicking autoteam (disconnect doesn't fire jointeam)
		CS_SwitchTeam(client, CS_TEAM_T);
		return Plugin_Handled;*/
		
		return Plugin_Continue;
	}

	//g_iSelectedTeam[client] = iTargetTeam;

	// Player isn't joining through autoteam
	g_bNeedsInitialTeam[client] = false;

	if (iCurrentTeam == iTargetTeam)
	{
		if (iTargetTeam == CS_TEAM_T)
		{
			RemoveFromGuardQueue(client);
		}

		SwapOnRoundEnd(client, iCurrentTeam);

		// Let's not have suicides because of stupid people joining same team
		return Plugin_Handled;
	}

	if (iCurrentTeam == CS_TEAM_CT && iTargetTeam == CS_TEAM_T && IsPlayerAlive(client))
	{
		PrintToChat(client, "You will be switched to the other team on round end so you don't miss the current round.");
		SwapOnRoundEnd(client, CS_TEAM_T);
		
		return Plugin_Handled;
	}

	if (iTargetTeam != CS_TEAM_CT || iCurrentTeam == iTargetTeam)
	{
		// @TODO: maybe if there's a CT already, check g_bNeedsInitialTeam and if that's set to true allow it?
		// People are able to join any team except CT freely (or ct if they were already in it, blocking joining same team is stupid)
		return Plugin_Continue;
	}

	return AddGuard(client);
}

/************************* EVENTS **************************/
void HookEvents()
{
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("teamchange_pending", Event_TeamchangePending, EventHookMode_Pre);
	HookEvent("jointeam_failed", Event_JoinTeamFailed, EventHookMode_Pre);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_Post);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int iUserId = event.GetInt("userid");
	int iClient = GetClientOfUserId(iUserId);
	int iTeam = event.GetInt("team");
	int iOldTeam = event.GetInt("oldteam");

	if (iTeam == CS_TEAM_CT)
	{
		if (g_bNeedsInitialTeam[iClient])
		{
			g_bNeedsInitialTeam[iClient] = false;
			dontBroadcast = true;
			//CS_SwitchTeam(iClient, CS_TEAM_T);

			// would it be possible to event.SetInt("iTeam", CS_TEAM_T); here? Probably best to just change teams again
			CreateTimer(0.0, Timer_SwitchTeam, iUserId);

			//return Plugin_Changed;
			return Plugin_Handled;
		}

		int iQueuePos = g_aGuardQueue.FindValue(iUserId);

		if (iQueuePos != -1)
		{
			g_aGuardQueue.Erase(iQueuePos);
		}

		g_aCTList.Push(iUserId);

		if (!g_bJoinedWillingly[iClient])
		{
			return Plugin_Continue;
		}
	}
	else if (iOldTeam == CS_TEAM_CT)
	{
		int iCTCount = GetTeamClientCount(CS_TEAM_CT);
		int iTCount = GetTeamClientCount(CS_TEAM_T);
		if (iCTCount == 0 && iTCount > 0)
		{
			// Let the teambalancer do it's job
			CS_TerminateRound(5.0, CSRoundEnd_CTSurrender);
		}

		int iCTPos = g_aCTList.FindValue(iUserId);
		if (iCTPos != -1)
		{
			g_aCTList.Erase(iCTPos);
		}
	}

	g_bJoinedWillingly[iClient] = true;

	return Plugin_Continue;
}

public Action Event_TeamchangePending(Event event, const char[] name, bool dontBroadcast)
{
    int iClient = GetClientOfUserId(event.GetInt("userid"));
    int iPendingTeam = event.GetInt("toteam");
    
    if (iPendingTeam == CS_TEAM_CT)
    {
        SetEntProp(iClient, Prop_Send, "m_iPendingTeamNum", CS_TEAM_T);
        return Plugin_Handled;
    }
        
    return Plugin_Continue;
}

public Action Event_JoinTeamFailed(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!client)
		return Plugin_Continue;

	int iReason = GetEventInt(event, "reason");

	int iTPlayerCount = GetTeamClientCount(CS_TEAM_T);
	int iCTPlayerCount = GetTeamClientCount(CS_TEAM_CT);

	switch(iReason)
	{
		case k_OneTeamChange:
		{
			//return Plugin_Continue;
		}

		case k_TeamsFull:
		{
			if (iCTPlayerCount == g_iCTSpawnCount && iTPlayerCount == g_iTSpawnCount)
            {
				LogError("There are not enough spawnpoints for both teams on %s", g_sMap);
				return Plugin_Continue;
            }
		}

		case k_TTeamFull:
		{
			if (iTPlayerCount == g_iTSpawnCount)
            {
				LogError("There are not enough spawnpoints for the T team on %s", g_sMap);
				return Plugin_Continue;
            }
		}

		case k_CTTeamFull:
		{
			/*if (iCTPlayerCount == g_iCTSpawnCount)
            {
				LogeError("There are not enough spawnpoints for the CT team on %s", g_sMap);
				return Plugin_Continue;
            }*/
            return Plugin_Continue;
		}
        
        case k_TooManyTerrorists:
        {
            
        }

		default:
		{
			return Plugin_Continue;
		}
	}
	
	CS_SwitchTeam(client, CS_TEAM_T);

	return Plugin_Handled;
}

public Action Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bLastRequestStarted = false;

	if(GameRules_GetProp("m_bWarmupPeriod") == 1)
	{
		return Plugin_Continue;
	}

	int iCTCount = GetTeamClientCount(CS_TEAM_CT);
	int iTCount = GetTeamClientCount(CS_TEAM_T);

	int iPlayerCount = iCTCount + iTCount;    

	//float flTargetRatio = FloatAdd(g_flTeamRatio, 1.0);
	//float flCTTargetCount = FloatDiv(view_as<float>(iPlayerCount), flTargetRatio);
	//int iCTTargetCount = RoundFloat(flCTTargetCount);

	int iCTTargetCount = RoundToCeil(iPlayerCount / (g_flTeamRatio + 1));

	if (iCTTargetCount == 0)
	{
		iCTTargetCount = 1;
	}

	int iNewCTs = iCTTargetCount - iCTCount;
    
	if (iNewCTs > 0)
	{
		ArrayList g_aTList = null;
		if (iNewCTs > g_aGuardQueue.Length)
		{
			// We will need more CT's than we have in the queue so prepare by getting all eligible T's
			g_aTList = new ArrayList();

			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsClientInGame(i) && GetClientTeam(i) == CS_TEAM_T && !IsCTBanned(i))
				{
					g_aTList.Push(i);
				}
			}
		}

		// We need to move some people to CT, let's start with the guard queue
		while (iNewCTs > 0)
		{
			int iGuard = SwapNextGuard();
			if (iGuard != -1)
			{
				PrintToChat(iGuard, "You have been swapped to CT because there were not enough of them.");
			}
			else
			{
				if (g_aTList.Length == 0)
				{
					// We've got no more eligible Terrorists to go to CT, abort
					break;
				}
				
				// Swap normal non-guard queue'ing player
				int iTargetIndex = GetRandomInt(0, g_aTList.Length - 1);
				iGuard = g_aTList.Get(iTargetIndex);
				g_aTList.Erase(iTargetIndex);

				g_bJoinedWillingly[iGuard] = false;

				CS_SwitchTeam(iGuard, CS_TEAM_CT);
			}

			iNewCTs--;
		}
	}
	else if (iNewCTs < 0)
	{
		while (iNewCTs < 0)
		{
            // @TODO: switch random CT?
			int iTargetIndex = g_aCTList.Length - 1;
			int iUserId = g_aCTList.Get(iTargetIndex);
			g_aCTList.Erase(iTargetIndex);
			int client = GetClientOfUserId(iUserId);

			if (client == 0)
			{
				LogError("[TB] Something went wrong while teambalancing, we've got a client 0 in CT list");
				continue;
			}
			
			// Should never be 0, but just to be sure
			CS_SwitchTeam(client, CS_TEAM_T);
			
			if (g_bJoinedWillingly[client])
			{
				// Add this client to the front of the queue
				g_aGuardQueue.ShiftUp(0);
				g_aGuardQueue.Set(0, iUserId);

				PrintToChat(client, "Since you were one of the last to join CT and we have too many currently, you have been switched back to the prisoner team and re-added to the guard queue.");
			}
			else
			{
				PrintToChat(client, "Since you were one of the last to join CT and we have too many currently, you have been switched back to the prisoner team.");
			}

			iNewCTs++;
		}
	}
    	
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if(GameRules_GetProp("m_bWarmupPeriod") == 1)
	{
        return Plugin_Continue;
    }
    
    // @TODO: Save round result and do calculations in RoundPreStart event so we have less duplicated code?
	// @TODO: clean this up, it looks shitty as fuck

    // Ratio change depends on how close / far we were from the target ratio
    int iWinner = g_bLastRequestStarted ? CS_TEAM_CT : event.GetInt("winner");
    int iCTCount = GetTeamClientCount(CS_TEAM_CT);
    int iPlayerCount = GetTeamClientCount(CS_TEAM_T) + iCTCount;

    int iCTTargetCount = RoundToCeil(iPlayerCount / (g_flTeamRatio + 1));
    if (iCTTargetCount == 0)
    {
        iCTTargetCount = 1;
    }

    int iDifference = iCTCount - iCTTargetCount;
    if (iDifference < 0)
    {
        iDifference = -iDifference;
    }

    float flRate = 1.0 - (iDifference / iCTTargetCount);

    if (iWinner == CS_TEAM_T)
    {
        // We want less T's for every CT
        //g_flTeamRatio -= iCTCount / iPlayerCount;
        g_flTeamRatio -= flRate * g_cContractRate.FloatValue;
        //g_flTeamRatio -= TEAM_CONTRACT_RATE;
    }
    else if (iWinner == CS_TEAM_CT)
    {
        // We want more T's for every CT
        //g_flTeamRatio += iCTCount / IPlayerCount;
        g_flTeamRatio += flRate * g_cExpandRate.FloatValue;
        //g_flTeamRatio += TEAM_EXPAND_RATE;
    }
    
    if (g_flTeamRatio > g_cMaxRatio.FloatValue)
    {
        g_flTeamRatio = g_cMaxRatio.FloatValue;
    }
    else if (g_flTeamRatio < g_cMinRatio.FloatValue)
    {
        g_flTeamRatio = g_cMinRatio.FloatValue;
    }
	
	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    // Easier way may be to Event.GetInt("index");
    int iUserId = event.GetInt("userid");
    int iClient = GetClientOfUserId(iUserId);
    
    if (iClient != 0)
    {
        return Plugin_Continue;
    }
    
    int iCTCount = GetTeamClientCount(CS_TEAM_CT);
    if (iCTCount > 1)
    {
        return Plugin_Continue;
    }
    
    SwapNextGuard();

    return Plugin_Continue;
}