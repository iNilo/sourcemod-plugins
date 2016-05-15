#if defined _warden_included
  #endinput
#endif
#define _warden_included

// Forwards
forward void OnNewWarden(int warden);
forward void OnWardenDisappeared();
forward Action OnTryingToBecomeWarden(int client);

// Natives

/*********************************************************
 * Checks if any warden exist
 *
 * @true on match , false if not
 *********************************************************/
native bool warden_exist();
native bool twarden_exist();

/*********************************************************
 * returns if client is warden
 *
 * @param client		The client to run the check on
 * @true on match, false if not		
 *********************************************************/
native bool warden_iswarden(client);
native bool twarden_iswarden(client);

/*********************************************************
 * Set a client as warden
 *
 * @param client		The client to set as warden
 * @NoReturn
 *********************************************************/
native void warden_set(client);
native void twarden_set(client);

/*********************************************************
 * Removes the current warden if he exists
 *
 * @param client		The warden client to remove
 * @NoReturn	
 *********************************************************/
native void warden_remove(client);
native void twarden_remove(client);