#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

bool g_bLadder[MAXPLAYERS+1];
float g_fLadder[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "Gravity fixes",
	author = "Bara & Meitis",
	version = "1.0",
	description = "Fixes gravity being reset when moving up/down ladders and reset it on round start",
	url = ""
};

public void OnPluginStart()
{
	HookEvent("round_prestart", Event_RoundStart);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if(!IsFakeClient(client))
	{
        if (GetEntityMoveType(client) == MOVETYPE_LADDER)
        {
            g_bLadder[client] = true;
        }
        else
        {
            if (g_bLadder[client])
            {
                SetEntityGravity(client, g_fLadder[client]);
                g_bLadder[client] = false;
            }
            else
            {
                g_fLadder[client] = GetEntityGravity(client);
            }
        }
	}
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		// If we don't do this, players that had low gravity and stayed on the ladder at round end kept their low gravity
		g_fLadder[i] = 1.0;
		
		// If we don't do this, players that had low gravity the previous round keep it
		if (IsClientInGame(i) && IsPlayerAlive(i)) {
			SetEntityGravity(i, 1.0);
		}
	}
}