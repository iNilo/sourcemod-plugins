#if defined _jb_core_included
 #endinput
#endif
#define _jb_core_included

forward void Core_OnConnectionEstablished();
forward void Core_OnServerConnected(int iServerId);
forward void Core_OnClientPutInServer(int client);
forward void Core_OnClientPostAdminCheck(int client, int clientId);
forward void Core_OnFirstJoin(int client);

/**
 * Gets the database if there is one
 *
 * @noparam
 * @return Database		database
 */
native Database Core_GetDatabase();

/**
 * Is the player alive or not?
 *
 * @param int			client
 * @return bool			alive
 */
native bool Core_IsPlayerAlive(int client);

/**
 * Get the ID the client is saved to the database with
 *
 * @param int			client
 * @return int			iClientId
 */
native int Core_GetClientId(int client);

/**
 * Get the client matching the current client ID, -1 if he isn't on the server currently
 *
 * @param int			iClientId
 * @return int			client
 */
native int Core_GetClientOfClientId(int iClientId);

/**
 * Get the ID for the currently active server
 *
 * @noparam
 */
native int Core_GetServerId();

/**
 * Processes a generic command target string, and resolves it to a list 
 * of clients or one client, based on filtering rules and a pattern.
 *
 * Note that you should use LoadTranslations("common.phrases") in OnPluginStart(), 
 * as that file is guaranteed to contain all of the translatable phrases that 
 * ProcessTargetString() will return.
 *
 * @param pattern		Pattern to find clients against.
 * @param admin			Admin performing the action, or 0 if the server.
 * @param targets		Array to hold targets.
 * @param max_targets	Maximum size of the targets array.
 * @param filter_flags	Filter flags.
 * @param target_name	Buffer to store the target name.
 * @param tn_maxlength	Maximum length of the target name buffer.
 * @param tn_is_ml		OUTPUT: Will be true if the target name buffer is an ML phrase,
 *						false if it is a normal string.
 * @return				If a multi-target pattern was used, the number of clients found 
 *						is returned.  If a single-target pattern was used, 1 is returned 
 *						if one valid client is found.  Otherwise, a COMMAND_TARGET reason 
 *						for failure is returned.
 */
native int Core_ProcessTargetString(const char[] pattern,
						   int admin, 
						   int[] targets,
						   int max_targets,
						   int filter_flags,
						   char[] target_name,
						   int tn_maxlength,
						   bool &tn_is_ml);

native void Core_SendAdminActivity(int admin, const char[] tag, const char[] format, any ...);

stock void Core_ShowActivity2(int admin, const char[] tag, const char[] format, any ...)
{
	int length = strlen(format)+255;
	char[] myFormattedString = new char[length];
	VFormat(myFormattedString, length, format, 4);
	
	Core_SendAdminActivity(admin, tag, myFormattedString);
}

stock int GetClientOfAuthId(char[] sAuthID)
{
	// @TODO: before someone overuses this too much, move this too core with stringmap search by steamid?
	if(strlen(sAuthID) < 11 || sAuthID[0]!='S' || sAuthID[6]=='I')
	{
		// This is a malformed steamid
		return -1;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}

		char sSteamidBuffer[32];
		GetClientAuthId(i, AuthId_Steam2, sSteamidBuffer, sizeof(sSteamidBuffer));

		if (StrEqual(sAuthID[8], sSteamidBuffer[8]))
		{
			return i;
		}
	}

	return -1;
}

// Credits to Zephyrus for this function
stock bool GetCommunityID(char[] AuthID, char[] FriendID, int size)
{
    if(strlen(AuthID) < 11 || AuthID[0]!='S' || AuthID[6]=='I')
    {
        FriendID[0] = 0;
        return false;
    }

    int iUpper = 765611979;
    int iFriendID = StringToInt(AuthID[10])*2 + 60265728 + AuthID[8]-48;

    int iDiv = iFriendID/100000000;
    int iIdx = 9-(iDiv?iDiv/10+1:0);
    iUpper += iDiv;
    
    IntToString(iFriendID, FriendID[iIdx], size-iIdx);
    iIdx = FriendID[9];
    IntToString(iUpper, FriendID, size);
    FriendID[9] = iIdx;

    return true;
}

// SMLIB excerpt but moved to new syntax
/**
 * Checks if string str starts with subString.
 * 
 *
 * @param str				String to check
 * @param subString			Sub-String to check in str
 * @return					True if str starts with subString, false otherwise.
 */
stock bool String_StartsWith(const char[] str, const char[] subString)
{
	int n = 0;
	while (subString[n] != '\0')
	{

		if (str[n] == '\0' || str[n] != subString[n]) {
			return false;
		}

		n++;
	}

	return true;
}

stock void SQL_Callback_Void(Database db, DBResultSet results, const char[] sError, any data)
{
	if (db == null || strlen(sError) != 0)
	{
		LogError("A database error occured: %s", sError);
	}
}