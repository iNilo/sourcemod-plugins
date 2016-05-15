#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <cnf_core>

#pragma newdecls required
#pragma semicolon 1

#define SAVEROUNDS 3

// @TODO: group menuhandlers
// @TODO: generalize player menu logic

int damageTaken[SAVEROUNDS][MAXPLAYERS+1][MAXPLAYERS+1];
int killedBy[SAVEROUNDS][MAXPLAYERS+1];
char playerNames[MAXPLAYERS+1][MAX_NAME_LENGTH];
int currentround = 0;
int targetChosen[MAXPLAYERS+1];

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	RegisterCommands();
	HookEvents();
	
	playerNames[0] = "World";
	
	for (int iRound = 0; iRound < SAVEROUNDS; iRound++)
	{
		for (int client = 1; client <= MAXPLAYERS; client++)
		{
			killedBy[iRound][client] = -1;
		}
	}
}

public void RegisterCommands()
{
	RegAdminCmd("sm_damagelog", Command_LogDamage, ADMFLAG_SLAY);
	RegAdminCmd("sm_dl", Command_LogDamage, ADMFLAG_SLAY);
	RegAdminCmd("sm_hurtlog", Command_LogDamage, ADMFLAG_SLAY);
	RegAdminCmd("sm_hl", Command_LogDamage, ADMFLAG_SLAY);
	RegAdminCmd("sm_killlog", Command_KillLog, ADMFLAG_SLAY);
	RegAdminCmd("sm_kl", Command_KillLog, ADMFLAG_SLAY);
	RegAdminCmd("sm_deathlog", Command_DeathLog, ADMFLAG_SLAY);
}

public void HookEvents()
{
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("round_end", Event_RoundEnd);
}

public Action Command_LogDamage(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, " \x07[SM]\x01 Usage: !damagelog\x03 <player/@all/@ct/@t>");
		return Plugin_Handled;
	}
   
	char arg1[32];
	GetCmdArg(1, arg1, 32);
   
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS]; int target_count; bool tn_is_ml;
   
	target_count = Core_ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
   
	if (target_count < 1)
	{
		ReplyToCommand(client, " \x07[SM]\x01 No matching client was found.");
		return Plugin_Handled;
	}
   
	if (target_count == 1)
	{
		targetChosen[client] = target_list[0];
		ShowRoundMenu(client, MenuHandler_DamageShow);
		
		return Plugin_Handled;
	}
	
	Menu menu = CreateMenu(MenuHandler_DamageNameChoice);
	menu.SetTitle("What player did you mean?");
	for (int i = 0; i < target_count; i++)
	{
		char name[32]; char targetid[3];
		GetClientName(target_list[i], name, sizeof(name));
		IntToString(target_list[i], targetid, sizeof(targetid));
		menu.AddItem(targetid, name);
	}
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}
 
public Action Command_DeathLog(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, " \x07[SM]\x01 Usage: !deathlog\x03 <player/@all/@ct/@t>");
		return Plugin_Handled;
	}
   
	char arg1[32];
	GetCmdArg(1, arg1, 32);
   
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS]; int target_count; bool tn_is_ml;
   
	target_count = Core_ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
   
	if (target_count < 1)
	{
		ReplyToCommand(client, " \x07[SM]\x01 No matching client was found.");
		return Plugin_Handled;
	}
	
	if (target_count == 1)
	{
		targetChosen[client] = target_list[0];
		ShowRoundMenu(client, MenuHandler_DeathShow);
		
		return Plugin_Handled;
	}

	Menu menu = CreateMenu(MenuHandler_DeathNameChoice);
	menu.SetTitle("What player did you mean?");
	for (int i = 0; i < target_count; i++)
	{
		char name[32]; char targetid[3];
		GetClientName(target_list[i], name, sizeof(name));
		IntToString(target_list[i], targetid, sizeof(targetid));
		menu.AddItem(targetid, name);
	}
	menu.Display(client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public Action Command_KillLog(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, " \x07[SM]\x01 Usage: !killlog\x03 <player/@all/@ct/@t>");
		return Plugin_Handled;
	}
   
	char arg1[32];
	GetCmdArg(1, arg1, 32);
   
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS]; int target_count; bool tn_is_ml;
   
	target_count = ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_CONNECTED, target_name, sizeof(target_name), tn_is_ml);
   
	if (target_count < 1)
	{
		if (StrEqual(arg1, "world", false))
		{
			targetChosen[client] = 0;
			ShowRoundMenu(client, MenuHandler_KillShow);
		}
		else ReplyToCommand(client, " \x07[SM]\x01 No matching client was found.");
		return Plugin_Handled;
	}
	
	if (target_count == 1)
	{
		targetChosen[client] = target_list[0];
		ShowRoundMenu(client, MenuHandler_KillShow);
		
		return Plugin_Handled;
	}
	
	Menu menu = CreateMenu(MenuHandler_KillNameChoice);
	menu.SetTitle("What player did you mean?");
	// @TODO: replace below logic with AddTargetsToMenu
    for (int i = 0; i < target_count; i++)
	{
		char name[32]; char targetid[3];
		GetClientName(target_list[i], name, sizeof(name));
		IntToString(target_list[i], targetid, sizeof(targetid));
		menu.AddItem(targetid, name);
	}
	menu.Display(client, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victimId = GetClientOfUserId(event.GetInt("userid"));
	int attackerId = GetClientOfUserId(event.GetInt("attacker"));
	
	killedBy[currentround][victimId] = attackerId;
	return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int victimId = GetClientOfUserId(event.GetInt("userid"));
	int attackerId = GetClientOfUserId(event.GetInt("attacker"));
	int damage = event.GetInt("dmg_health");
	
	damageTaken[currentround][victimId][attackerId] += damage;
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	GetClientName(client, playerNames[client], MAX_NAME_LENGTH);
	
	for (int i = 0; i <= MaxClients; i++)
	{
		damageTaken[currentround][client][i] = 0;
	}
	killedBy[currentround][client] = -1;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	currentround = (currentround + 1) % SAVEROUNDS;
	return Plugin_Continue;
}

public int MenuHandler_KillNameChoice(Menu menu, MenuAction action, int param1, int param2)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[3];
		menu.GetItem(param2, info, sizeof(info));
		targetChosen[param1] = StringToInt(info);
		ShowRoundMenu(param1, MenuHandler_KillShow);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowRoundMenu(param1, MenuHandler_KillShow);
	}
}

stock void ShowKillMenu(int client, int round)
{
	Menu menu = CreateMenu(MenuHandler_KillNameChoice);
	menu.SetTitle("%N killed", targetChosen[client]);
	int count;
	for (int j = 1; j <= MaxClients; j++)
	{
		if (IsClientInGame(j) && killedBy[round][j] == targetChosen[client]) {
			char name[32];
			GetClientName(j, name, sizeof(name));
			menu.AddItem("", name, ITEMDRAW_DISABLED);
			count++;
		}
	}
	if (count == 0) menu.AddItem("", "DIDN'T KILL", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_DamageNameChoice(Menu menu, MenuAction action, int param1, int param2)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[3];
		menu.GetItem(param2, info, sizeof(info));
		targetChosen[param1] = StringToInt(info);
		ShowRoundMenu(param1, MenuHandler_DamageShow);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowRoundMenu(param1, MenuHandler_DamageShow);
	}
}

stock void ShowDamageMenu(int client, int round)
{
	Menu menu = CreateMenu(MenuHandler_DamageNameChoice);
	menu.SetTitle("%N damaged by", targetChosen[client]);
	int count;
	for (int i = 0; i <= MaxClients; i++)
	{
		if (damageTaken[round][targetChosen[client]][i] != 0)
		{
			char damagelog[40];
			Format(damagelog, sizeof(damagelog), "%s - %d", playerNames[i], damageTaken[round][targetChosen[client]][i]);
			menu.AddItem("", damagelog, ITEMDRAW_DISABLED);
			count++;
		}
	}
	if (count == 0) menu.AddItem("", "NOT DAMAGED", ITEMDRAW_DISABLED);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int GetPreviousRound(int round)
{
	int newround = round - 1;
	if (newround < 0) newround = SAVEROUNDS-1;
	return newround;
}

stock void ShowRoundMenu(int client, MenuHandler handler)
{
	Menu menu = CreateMenu(handler);
	menu.SetTitle("What round?");
	char round[3];
	IntToString(currentround, round, sizeof(round));
	menu.AddItem(round, "Current round");
	int previousround = currentround;
	int roundsAgo;
	char display[18];
	while((previousround = GetPreviousRound(previousround)) != currentround)
	{
		Format(display, sizeof(display), "%d round(s) ago", ++roundsAgo);
		IntToString(previousround, round, sizeof(round));
		menu.AddItem(round, display);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_DamageShow(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[3];
		menu.GetItem(param2, info, sizeof(info));
		int round = StringToInt(info);
		ShowDamageMenu(param1, round);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int MenuHandler_KillShow(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[3];
		menu.GetItem(param2, info, sizeof(info));
		int round = StringToInt(info);
		ShowKillMenu(param1, round);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int MenuHandler_DeathNameChoice(Menu menu, MenuAction action, int param1, int param2)
{
	/* If an option was selected, tell the client about the item. */
	if (action == MenuAction_Select)
	{
		char info[3];
		menu.GetItem(param2, info, sizeof(info));
		targetChosen[param1] = StringToInt(info);
		ShowRoundMenu(param1, MenuHandler_DeathShow);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowRoundMenu(param1, MenuHandler_DeathShow);
	}
}

public int MenuHandler_DeathShow(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[3];
		menu.GetItem(param2, info, sizeof(info));
		int round = StringToInt(info);
		ShowDeathMenu(param1, round);
	}
	/* If the menu has ended, destroy it */
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock void ShowDeathMenu(int client, int round)
{
	Menu menu = CreateMenu(MenuHandler_DeathNameChoice);
	menu.SetTitle("%N killed by", targetChosen[client]);
	if (killedBy[round][targetChosen[client]] < 0)
	{
		menu.AddItem("", "DIDN'T DIE", ITEMDRAW_DISABLED);
	}
	else
	{
		char deathlog[40];
		Format(deathlog, sizeof(deathlog), "%s - %d", playerNames[killedBy[round][targetChosen[client]]], damageTaken[round][targetChosen[client]][killedBy[round][targetChosen[client]]]);
		menu.AddItem("", deathlog, ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}