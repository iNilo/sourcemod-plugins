#if defined _warden_included
  #endinput
#endif
#define _warden_included

/*********************************************************
 * Checks if any warden exist
 *
 * @true on match , false if not
 *********************************************************/
native warden_exist();
native twarden_exist();

/*********************************************************
 * returns if client is warden
 *
 * @param client		The client to run the check on
 * @true on match, false if not		
 *********************************************************/
native warden_iswarden(client);
native twarden_iswarden(client);

/*********************************************************
 * Set a client as warden
 *
 * @param client		The client to set as warden
 * @NoReturn
 *********************************************************/
native warden_set(client);
native twarden_set(client);

/*********************************************************
 * Removes the current warden if he exists
 *
 * @param client		The warden client to remove
 * @NoReturn	
 *********************************************************/
native warden_remove(client);
native twarden_remove(client);