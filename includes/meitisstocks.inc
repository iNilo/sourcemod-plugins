#if defined _meitisstocks_included
 #endinput
#endif
#define _meitisstocks_included

stock void PrintToAdminConsole(const char[] text, any ...)
{
	char buffer[255];
	VFormat(buffer, 255, text, 2);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && CheckCommandAccess(i, "sm_chat", ADMFLAG_CHAT))
		{
			PrintToConsole(i, buffer);
		}
	}
}

stock void PrintToAdminChat(const char[] text, any ...)
{
	char buffer[255];
	VFormat(buffer, 255, text, 2);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && CheckCommandAccess(i, "sm_chat", ADMFLAG_CHAT))
		{
			PrintToChat(i, buffer);
		}
	}
}

stock bool IsValidClient(int client)
{
	if (0 < client <= MaxClients && !IsFakeClient(client) && !IsClientSourceTV(client))
	{
		return true;
	}
	
	return false;
}

stock int GetTeamAliveClientCount(int team)
{
	int count;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && GetClientTeam(i) == team)
		{
			count++;
		}
	}
	
	return count;
}