#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

#define SOUND_GIVEAWAY_START "forward.wav"
#define SOUND_GIVEAWAY_ENTER ""
#define SOUND_GIVEAWAY_END ""
#define SOUND_GIVEAWAY_CANCELED ""

ConVar g_cvPlaySounds;
ConVar g_cvGiveawayTime;

bool g_bActiveGiveaway = false;
ArrayList g_alParticipants;

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
	
	RegAdminCmd("sm_gstart", CMD_CreateGiveaway, ADMFLAG_GENERIC, "Starts a giveaway");
	RegAdminCmd("sm_gstop", CMD_StopGiveaway, ADMFLAG_GENERIC, "Stops the current giveaway");
	RegAdminCmd("sm_gcancel", CMD_CancelGiveaway, ADMFLAG_GENERIC, "Cancels the current giveaway");
	RegAdminCmd("sm_gparticipants", CMD_Participants, ADMFLAG_GENERIC, "Shows the participants of the current giveaway.");
	
	RegConsoleCmd("sm_enter", CMD_Enter, "Enter the giveaway!");
	RegConsoleCmd("sm_leave", CMD_Leave, "Leave the giveaway!");
	
	g_alParticipants = new ArrayList();
	
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

public Action CMD_CreateGiveaway(int client, int args) {
	if (g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayInProgress");
		return Plugin_Handled;
	}
	
	// Get prize string and format message accordingly
	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	TrimString(arg);
	
	char message[512];
	if (arg[0] == '\0') {
		Format(message, sizeof(message), "%t", "GiveawayStarting_Center", g_cvGiveawayTime.IntValue);
	}
	else {
		Format(message, sizeof(message), "%t", "GiveawayStarting_Center_Prize", arg, g_cvGiveawayTime.IntValue);
	}
	
	// Set buffers
	g_bActiveGiveaway = true;
	
	// Send message to center
	PrintCenterTextAll(message);
	
	// Send message to chat
	if (arg[0] == '\0') {
		MC_PrintToChatAll("%t", "GiveawayStarting_Chat", g_cvGiveawayTime.IntValue);
	}
	else {
		MC_PrintToChatAll("%t", "GiveawayStarting_Chat_Prize", arg, g_cvGiveawayTime.IntValue);
	}
	
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
		// Get winner
		int random = GetRandomInt(0, g_alParticipants.Length - 1);
		int winner = GetClientOfUserId(g_alParticipants.Get(random));
		
		// Announce winner
		PrintCenterTextAll("%t", "GiveawayWinnerAnnouncement_Center", winner);
		MC_PrintToChatAll("%t", "GiveawayWinnerAnnouncement_Chat", winner);
		
		// Play sound if enabled
		PlaySound("giveaway_end.wav");
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
	g_alParticipants.Push(GetClientUserId(client));
	
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
	
	Menu menu = new Menu(ParticipantsMenu);
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

public int ParticipantsMenu(Menu menu, MenuAction action, int param1, int param2) {  }

void PlaySound(char[] sound, int client = 0) {
	if (g_cvPlaySounds.BoolValue) {
		client ? EmitSoundToClient(client, sound) : EmitSoundToAll(sound);
	}
} 