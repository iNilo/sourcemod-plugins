#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
//#include <smlib>

#pragma semicolon 1
#pragma newdecls required

public void OnPluginStart()
{
	HookEvent("player_hurt", Event_PlayerHurt);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (GetClientHealth(client) >= 1)
	{
		// We only want dead people before death event fires
		return Plugin_Continue;
	}

	int iWeapon = GetPlayerWeaponSlot(client, 4);
	if (iWeapon != -1)
	{
		CS_DropWeapon(client, iWeapon, true, false);
	}

	return Plugin_Continue;
}

public Action OnWeaponCanUse(int client, int weapon)
{
	if(!IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	if (!IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	
	char sWeapon[32];
	GetEntityClassname(weapon, sWeapon, sizeof(sWeapon));
	
	if(StrEqual(sWeapon[7], "c4") && GetPlayerWeaponSlot(client, 4) != -1)
	{
		return Plugin_Stop;
	}
	
	/*if (HasWeapon(client, sWeapon))
	{
		return Plugin_Stop;
	}*/
	return Plugin_Continue;
}

/*public bool HasWeapon(int client, char[] searchWeapon)
{
	//Client_HasWeapon can replace
	new String:szWeapon[32];
	LOOP_CLIENTWEAPONS(client, weapon, index) {
		GetEntityClassname(weapon, szWeapon, sizeof(szWeapon));
		if (StrEqual(searchWeapon, szWeapon, false) == true) {
			return true;
		}
	}
	
	return false;
}*/