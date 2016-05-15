#if defined _timedpunishments_included
 #endinput
#endif
#define _timedpunishments_included

/*enum Countdown
{
	COUNTDOWN_CONSTANT = 0,
	COUNTDOWN_ONLINE = 1,
	COUNTDOWN_ALIVE = 2,
	COUNTDOWN_CURRENTMAP = 3
};*/

#define COUNTDOWN_CONSTANT		0
#define COUNTDOWN_ONLINE		1
#define COUNTDOWN_ALIVE			2
#define COUNTDOWN_CURRENTMAP	3

native int TimedPunishment_RegisterPunishment(char[] startcommand, char[] stopcommand, char[] name, int flags, int cntdown, bool allowMultipleTargets, bool allowOtherServerPunishments, char[] startCallback, char[] stopCallback, char[] joinCallback, char[] leaveCallback);
//native TimedPunishment_RegisterPunishment(Handle plugin, char[] command, char[] name, Countdown cntdown, Function start, Function stop, Function join, Function leave);

native DataPack TimedPunishment_GetPunishmentInformation(int client, int iPunishmentType);