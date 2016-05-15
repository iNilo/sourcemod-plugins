#if defined _map_variables_included
 #endinput
#endif
#define _map_variables_included

#define NO_MAPVARIABLE_AVAILABLE -1

forward void OnMapVariablesFetched();

/**
 * Gets the value for the mapvariable as string
 *
 */
native int GetMapVariableString(char[] sKey, char[] sValueBuffer, int iLength);

/**
 * Gets the value for the mapvariable as integer
 *
 */
native int GetMapVariableInt(char[] sKey, int &iValue);

/**
 * Get the value for the mapvariable as float
 *
 */
native int GetMapVariableFloat(char[] sKey, float &fValue);

native int SetMapVariableString(char[] sKey, char[] sValue);

native int SetMapVariableInt(char[] sKey, int iValue);

native int SetMapVariableFloat(char[] sKey, float fValue);