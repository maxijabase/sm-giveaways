/*
**
*/
#if defined _giveaways_included
#endinput
#endif
#define _giveaways_included

/*
* Called when a giveaway is about to start
*
* @param client			The creator of the giveaway
* @param prize 			The specified prize
* @return 				Plugin_Continue to allow the giveaway to start, Plugin_Handled otherwise
*/
forward Action Giveaways_OnGiveawayStart(int client, const char[] prize);


/*
* Called when a giveaway has ended
*
* @param creator		The creator of the giveaway
* @param winner 		The winner of the giveaway
* @param prize 			The specified prize
* @noreturn 				
*/
forward void Giveaways_OnGiveawayEnded(int creator, int winner, int participants, const char[] prize);


/*
* Called when a user enters the giveaway
*
* @param client			The participant
* @return 				Plugin_Continue to allow the user to participate, Plugin_Handled otherwise
*/
forward Action Giveaways_OnClientEnter(int client);

/*
* Called when a user leaves the giveaway
*
* @param client			The participant
* @return 				Plugin_Continue to allow the user to leave, Plugin_Handled otherwise
*/
forward Action Giveaways_OnClientLeave(int client);

/*
* Called when a giveaway gets canceled
*
* @return 				Plugin_Continue to allow the giveaway to get canceled, Plugin_Handled otherwise
*/
forward Action Giveaways_OnGiveawayCancel();

public SharedPlugin __pl_giveaways = 
{
	name = "giveaways", 
	file = "giveaways.smx", 
	#if defined REQUIRE_PLUGIN
	required = 1, 
	#else
	required = 0, 
	#endif
};
