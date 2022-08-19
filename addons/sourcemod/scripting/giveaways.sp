#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

ConVar g_cvPlaySounds;
ConVar g_cvGiveawayTime;
ConVar g_cvWinnerCooldown;

bool g_bActiveGiveaway = false;
ArrayList g_alParticipants;
StringMap g_smPastWinners;

public Plugin myinfo = {
	name = "Giveaways!", 
	author = "ampere", 
	description = "Allows server admins to start giveaways.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/maxijabase"
};

public void OnPluginStart() {
	
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("giveaways");
	
	CreateConVar("sm_giveaways_version", PLUGIN_VERSION, "Standar plugin version ConVar. Please don't change me!", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	g_cvPlaySounds = AutoExecConfig_CreateConVar("sm_giveaways_sounds", "1", "Play start, enter, and end sounds.");
	g_cvGiveawayTime = AutoExecConfig_CreateConVar("sm_giveaways_time", "60", "Amount of time before the giveaway entry time stops");
	g_cvWinnerCooldown = AutoExecConfig_CreateConVar("sm_giveaways_winner_cooldown", "1", "Amount of giveaways that must pass before someone that has won, can win again.");
	
	RegAdminCmd("sm_gstart", CMD_CreateGiveaway, ADMFLAG_GENERIC, "Starts a giveaway");
	RegAdminCmd("sm_gstop", CMD_StopGiveaway, ADMFLAG_GENERIC, "Stops the current giveaway");
	RegAdminCmd("sm_gcancel", CMD_CancelGiveaway, ADMFLAG_GENERIC, "Cancels the current giveaway");
	RegAdminCmd("sm_gparticipants", CMD_Participants, ADMFLAG_GENERIC, "Shows the participants of the current giveaway.");
	
	RegConsoleCmd("sm_enter", CMD_Enter, "Enter the giveaway!");
	RegConsoleCmd("sm_leave", CMD_Leave, "Leave the giveaway!");
	
	g_alParticipants = new ArrayList();
	g_smPastWinners = new StringMap();
	
	LoadTranslations("giveaways.phrases");
	
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
}

public void OnMapStart() {
	PrecacheSound("giveaway_starting.wav");
	PrecacheSound("giveaway_entered.wav");
	PrecacheSound("giveaway_end.wav");
	PrecacheSound("giveaway_canceled.wav");
	AddFileToDownloadsTable("sound/giveaway_starting.wav");
	AddFileToDownloadsTable("sound/giveaway_entered.wav");
	AddFileToDownloadsTable("sound/giveaway_end.wav");
	AddFileToDownloadsTable("sound/giveaway_canceled.wav");
}

public void OnMapEnd() {
	g_alParticipants.Clear();
	g_smPastWinners.Clear();
}

public Action CMD_CreateGiveaway(int client, int args) {
	// Check for current giveaway
	if (g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayInProgress");
		return Plugin_Handled;
	}
	
	int time = g_cvGiveawayTime.IntValue;
	
	// Get prize string and format messages accordingly
	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	TrimString(arg);
	
	char messageCenter[512];
	char messageChat[512];
	if (arg[0] == '\0') {
		Format(messageCenter, sizeof(messageCenter), "%t", "GiveawayStarting_Center", time);
		Format(messageChat, sizeof(messageChat), "%t", "GiveawayStarting_Chat", time);
	}
	else {
		Format(messageCenter, sizeof(messageCenter), "%t", "GiveawayStarting_Center_Prize", arg, time);
		Format(messageChat, sizeof(messageChat), "%t", "GiveawayStarting_Chat_Prize", arg, time);
	}
	
	// Set buffers
	g_bActiveGiveaway = true;
	
	// Send messages
	PrintCenterTextAll(messageCenter);
	MC_PrintToChatAll(messageChat);
	
	// Send sounds if enabled
	PlaySound("giveaway_starting.wav");
	
	// Send timer
	CreateTimer(g_cvGiveawayTime.FloatValue, TimerEndCallback);
	return Plugin_Handled;
}

public Action TimerEndCallback(Handle timer) {
	if (g_bActiveGiveaway) {
		CMD_StopGiveaway(0, 0);
	}
}

public Action CMD_StopGiveaway(int client, int args) {
	// Check if there's an ongoing giveaway
	if (!g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayNone");
		return Plugin_Handled;
	}
	
	// Check if there are potential winners
	if (g_alParticipants.Length == 0) {
		PrintCenterTextAll("%t", "GiveawayNoWinners_Center");
		MC_PrintToChatAll("%t", "GiveawayNoWinners_Chat");
		
		// Play sound if enabled
		PlaySound("giveaway_canceled.wav");
	}
	else {
		// Filter out people that are not supposed to be participating
		FilterParticipants();
		
		// Get winner
		int random = GetRandomInt(0, g_alParticipants.Length - 1);
		int winner = GetClientOfUserId(g_alParticipants.Get(random));
		
		// Announce winner
		PrintCenterTextAll("%t", "GiveawayWinnerAnnouncement_Center", winner);
		MC_PrintToChatAll("%t", "GiveawayWinnerAnnouncement_Chat", winner);
		
		// Play sound if enabled
		PlaySound("giveaway_end.wav");
		
		// Advance cooldowns
		AdvanceCooldowns();
		
		// Add winner to cooldown list if enabled
		
		if (g_cvWinnerCooldown.IntValue > 0) {
			char steamid[32];
			GetClientAuthId(winner, AuthId_Steam2, steamid, sizeof(steamid));
			g_smPastWinners.SetValue(steamid, 0);
		}
	}
	
	// Set flags and buffers
	g_bActiveGiveaway = false;
	g_alParticipants.Clear();
	
	return Plugin_Handled;
}

public Action CMD_CancelGiveaway(int client, int args) {
	// Check if there's an ongoing giveaway
	if (!g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayNone");
		return Plugin_Handled;
	}
	
	// Cancel giveaway
	g_bActiveGiveaway = false;
	g_alParticipants.Clear();
	
	// Announce
	PrintCenterTextAll("%t", "GiveawayCanceled_Center");
	MC_PrintToChatAll("%t", "GiveawayCanceled_Chat");
	
	// Play sound if enables
	PlaySound("giveaway_canceled.wav");
	
	return Plugin_Handled;
}

public Action CMD_Enter(int client, int args) {
	// Check for current giveaways
	if (!g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayNone");
		return Plugin_Handled;
	}
	
	// Check if he's already participating
	int userid = GetClientUserId(client);
	if (g_alParticipants.FindValue(userid) != -1) {
		MC_ReplyToCommand(client, "%t", "GiveawayAlreadyParticipating");
		return Plugin_Handled;
	}
	
	// Push to participants list
	g_alParticipants.Push(userid);
	
	// Announce participance
	MC_ReplyToCommand(client, "%t", "GiveawayEntered");
	
	// Play sound if enabled
	PlaySound("giveaway_entered.wav", client);
	
	return Plugin_Handled;
}

public Action CMD_Leave(int client, int args) {
	// Check for current giveaway
	if (!g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayNone");
		return Plugin_Handled;
	}
	
	int participant = g_alParticipants.FindValue(GetClientUserId(client));
	
	// Check if he was participating
	if (participant == -1) {
		MC_ReplyToCommand(client, "%t", "GiveawayNotParticipating");
		return Plugin_Handled;
	}
	
	// Delete him from participants
	g_alParticipants.Erase(participant);
	
	// Play sound if enabled
	PlaySound("giveaway_canceled.wav", client);
	
	// Inform
	MC_ReplyToCommand(client, "%t", "GiveawayLeft");
	return Plugin_Handled;
}

public Action CMD_Participants(int client, int args) {
	// Check for current giveaway
	if (!g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayNone");
		return Plugin_Handled;
	}
	
	int participants = g_alParticipants.Length;
	
	// Check for participants
	if (participants == 0) {
		MC_ReplyToCommand(client, "%t", "GiveawayNoParticipants");
		return Plugin_Handled;
	}
	
	Menu menu = new Menu(EmptyMenu);
	menu.SetTitle("%d participants", participants);
	
	for (int i = 0; i < participants; i++) {
		int participant = GetClientOfUserId(g_alParticipants.Get(i));
		char name[MAX_NAME_LENGTH];
		Format(name, sizeof(name), "%N", participant);
		menu.AddItem(name, name, ITEMDRAW_DISABLED);
	}
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int EmptyMenu(Menu menu, MenuAction action, int param1, int param2) {  }

void PlaySound(char[] sound, int client = 0) {
	if (g_cvPlaySounds.BoolValue) {
		client ? EmitSoundToClient(client, sound) : EmitSoundToAll(sound);
	}
}

void AdvanceCooldowns() {
	// Advance cooldown in past winners (thanks Doggy for the snippet)
	StringMapSnapshot snapshot = g_smPastWinners.Snapshot();
	for (int i = 0; i < snapshot.Length; i++)
	{
		// Get key...
		int bufferSize = snapshot.KeyBufferSize(i);
		char[] key = new char[bufferSize];
		snapshot.GetKey(i, key, bufferSize);
		
		// ...to get value
		int value;
		g_smPastWinners.GetValue(key, value);
		
		// Advance...
		int next = value + 1;
		
		// If next is below cooldown, keep waiting, otherwise he's free to go
		if (next < g_cvWinnerCooldown.IntValue) {
			g_smPastWinners.SetValue(key, next);
		}
		else {
			g_smPastWinners.Remove(key);
		}
	}
	delete snapshot;
}

bool CanParticipate(int client) {
	// Get auth
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	// And check if he's even won, and if he's still below cooldown
	int passed;
	if (g_smPastWinners.GetValue(steamid, passed)) {
		return passed >= g_cvWinnerCooldown.IntValue;
	}
	
	return true;
}

void FilterParticipants() {
	for (int i = 0; i < g_alParticipants.Length; i++) {
		int client = GetClientOfUserId(g_alParticipants.Get(i));
		if (!CanParticipate(client)) {
			g_alParticipants.Erase(i);
		}
	}
} 