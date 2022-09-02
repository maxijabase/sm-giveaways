#include "include/giveaways"

public Action Giveaways_OnGiveawayStart(int client, const char[] prize) {
	PrintToChat(client, "Giveaway allowed! client starting the giveaway is %N and prize is %s", client, prize);
	return Plugin_Continue;
}

public Action Giveaways_OnClientEnter(int client) {
	PrintToChatAll("%N entered the giveaway! we will ALLOW him!", client);
	return Plugin_Continue;
}

public Action Giveaways_OnClientLeave(int client) {
	PrintToChatAll("%N WANTS TO LEAVE! ALLOWED!", client);
	return Plugin_Continue;
}

public void Giveaways_OnGiveawayEnded(int creator, int winner, int participants, const char[] prize) {
	PrintToServer("giveaway ended! started by: %N - won by: %N - participants: %d - prize: %s", creator, winner, participants, prize);
}

public Action Giveaways_OnGiveawayCancel(int creator, int cancelator) {
	PrintToServer("the giveaway created by %N wants to be cancelated by %N! DENIED!", creator, cancelator);
	return Plugin_Handled;
}