#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.1"

ConVar g_cvPlaySounds;
ConVar g_cvGiveawayTime;
ConVar g_cvWinnerCooldown;
ConVar g_cvCountdown;
ConVar g_cvSendMenuToWinner;

GlobalForward g_gfOnGiveawayStart;
GlobalForward g_gfOnGiveawayEnded;
GlobalForward g_gfOnClientEnter;
GlobalForward g_gfOnClientLeave;
GlobalForward g_gfOnGiveawayCancel;

bool g_bActiveGiveaway = false;
bool g_bSuspensePlayed = false;
int g_iCountdownInterval;
int g_iGiveawayCreator;
char g_cPrize[128];
ArrayList g_alParticipants;
StringMap g_smPastWinners;

public Plugin myinfo = {
	name = "Giveaways!", 
	author = "ampere", 
	description = "Allows server admins to start giveaways.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/maxijabase"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("giveaways");
	
	g_gfOnGiveawayStart = new GlobalForward("Giveaways_OnGiveawayStart", ET_Event, Param_Cell, Param_String);
	g_gfOnGiveawayEnded = new GlobalForward("Giveaways_OnGiveawayEnded", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
	g_gfOnClientEnter = new GlobalForward("Giveaways_OnClientEnter", ET_Event, Param_Cell);
	g_gfOnClientLeave = new GlobalForward("Giveaways_OnClientLeave", ET_Event, Param_Cell, Param_String);
	g_gfOnGiveawayCancel = new GlobalForward("Giveaways_OnGiveawayCancel", ET_Event, Param_Cell, Param_Cell);
}

public void OnPluginStart() {
	
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_SetFile("giveaways");
	
	CreateConVar("sm_giveaways_version", PLUGIN_VERSION, "Standar plugin version ConVar. Please don't change me!", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	g_cvPlaySounds = AutoExecConfig_CreateConVar("sm_giveaways_sounds", "1", "Play start, enter, and end sounds.");
	g_cvGiveawayTime = AutoExecConfig_CreateConVar("sm_giveaways_time", "60", "Amount of time before the giveaway entry time stops");
	g_cvWinnerCooldown = AutoExecConfig_CreateConVar("sm_giveaways_winner_cooldown", "1", "Amount of giveaways that must pass before someone that has won, can win again.");
	g_cvCountdown = AutoExecConfig_CreateConVar("sm_giveaways_countdown", "1", "Enable 5 second countdown in center screen and chat.");
	g_cvSendMenuToWinner = AutoExecConfig_CreateConVar("sm_giveaways_winner_sendmenu", "1", "Send an in-game menu (panel) to the winner with customizable details (in translations file).");
	
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
	PrecacheSound("giveaway_suspense.wav");
	PrecacheSound("giveaway_end.wav");
	PrecacheSound("giveaway_canceled.wav");
	AddFileToDownloadsTable("sound/giveaway_starting.wav");
	AddFileToDownloadsTable("sound/giveaway_entered.wav");
	AddFileToDownloadsTable("sound/giveaway_suspense.wav");
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
	
	// Get prize string
	char arg[64];
	GetCmdArgString(arg, sizeof(arg));
	TrimString(arg);
	
	// Check forward
	if (!Forward_OnGiveawayStart(client, arg)) {
		return Plugin_Handled;
	}
	
	// Format messages
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
	g_bSuspensePlayed = false;
	g_iGiveawayCreator = GetClientUserId(client);
	strcopy(g_cPrize, sizeof(g_cPrize), arg);
	
	// Send messages
	PrintCenterTextAll(messageCenter);
	MC_PrintToChatAll(messageChat);
	
	// Send sounds if enabled
	PlaySound("giveaway_starting.wav");
	
	// Enable direct timer or countdown timer depending on cvar setting
	if (g_cvCountdown.BoolValue) {
		g_iCountdownInterval = time;
		CreateTimer(1.0, Timer_CountdownCallback, _, TIMER_REPEAT);
	}
	else {
		CreateTimer(g_cvGiveawayTime.FloatValue, Timer_EndCallback);
	}
	
	return Plugin_Handled;
}

public Action Timer_EndCallback(Handle timer) {
	if (g_bActiveGiveaway) {
		CMD_StopGiveaway(0, 0);
	}
}

public Action Timer_CountdownCallback(Handle timer) {
	if (g_iCountdownInterval == 0) {
		CMD_StopGiveaway(0, 0);
		return Plugin_Stop;
	}
	
	if (g_iCountdownInterval <= 5) {
		if (!g_bActiveGiveaway) {
			return Plugin_Stop;
		}
		
		if (!g_bSuspensePlayed) {
			PlaySound("giveaway_suspense.wav");
			g_bSuspensePlayed = true;
		}
		PrintCenterTextAll("%t", "GiveawayCountdown_Center", g_iCountdownInterval);
		MC_PrintToChatAll("%t", "GiveawayCountdown_Chat", g_iCountdownInterval);
	}
	g_iCountdownInterval--;
	return Plugin_Continue;
}

public Action CMD_StopGiveaway(int client, int args) {
	// Check if there's an ongoing giveaway
	if (!g_bActiveGiveaway) {
		MC_ReplyToCommand(client, "%t", "GiveawayNone");
		return Plugin_Handled;
	}
	
	int random, winner;
	
	// Filter out people that are not supposed to be participating
	FilterParticipants();
	
	// Check if there are potential winners
	if (g_alParticipants.Length == 0) {
		PrintCenterTextAll("%t", "GiveawayNoWinners_Center");
		MC_PrintToChatAll("%t", "GiveawayNoWinners_Chat");
		
		// Play sound if enabled
		PlaySound("giveaway_canceled.wav");
	}
	else {
		// Get winner
		do {
			random = GetRandomInt(0, g_alParticipants.Length - 1);
			winner = GetClientOfUserId(g_alParticipants.Get(random));
		} while (winner == 0);
		
		// Announce winner
		PrintCenterTextAll("%t", "GiveawayWinnerAnnouncement_Center", winner);
		MC_PrintToChatAll("%t", "GiveawayWinnerAnnouncement_Chat", winner);
		
		// Play sound if enabled
		PlaySound("giveaway_end.wav");
		
		// Send info menu to winner if enabled
		if (g_cvSendMenuToWinner.BoolValue) {
			SendWinnerMenu(winner);
		}
		
		// Add winner to cooldown list if enabled
		if (g_cvWinnerCooldown.IntValue > 0) {
			char steamid[32];
			GetClientAuthId(winner, AuthId_Steam2, steamid, sizeof(steamid));
			g_smPastWinners.SetValue(steamid, 0);
		}
	}
	
	// Send forward
	Forward_OnGiveawayEnded(GetClientOfUserId(g_iGiveawayCreator), winner, g_alParticipants.Length, g_cPrize);
	
	// Advance cooldowns
	AdvanceCooldowns();
	
	// Set flags and buffers
	g_bActiveGiveaway = false;
	g_alParticipants.Clear();
	g_iGiveawayCreator = 0;
	g_cPrize[0] = '\0';
	
	return Plugin_Handled;
}

public Action CMD_CancelGiveaway(int client, int args) {
	// Check forward
	if (!Forward_OnGiveawayCancel(GetClientOfUserId(g_iGiveawayCreator), client)) {
		return Plugin_Handled;
	}
	
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
	// Check forward
	if (!Forward_OnClientEnter(client)) {
		return Plugin_Handled;
	}
	
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
	// Check forward
	if (!Forward_OnClientLeave(client)) {
		return Plugin_Handled;
	}
	
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

void FilterParticipants() {
	for (int i = 0; i < g_alParticipants.Length; i++) {
		int client = GetClientOfUserId(g_alParticipants.Get(i));
		if (!CanParticipate(client)) {
			g_alParticipants.Erase(i);
		}
	}
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

void SendWinnerMenu(int client) {
	Panel panel = new Panel();
	char panelTitle[64], panelBody[256], exitString[32];
	Format(panelTitle, sizeof(panelTitle), "%t", "GiveawayWinner_MenuTitle", client, g_cPrize);
	Format(panelBody, sizeof(panelBody), "%t", "GiveawayWinner_MenuBody", client, g_cPrize);
	Format(exitString, sizeof(exitString), "%t", "Exit");
	panel.SetTitle(panelTitle);
	panel.DrawText(" ");
	panel.DrawText(panelBody);
	panel.DrawText(" ");
	panel.CurrentKey = 10;
	panel.DrawItem(exitString);
	panel.Send(client, EmptyMenu, MENU_TIME_FOREVER);
}

/* Forwards */

bool Forward_OnGiveawayStart(int client, const char[] prize) {
	Action result;
	Call_StartForward(g_gfOnGiveawayStart);
	Call_PushCell(client);
	Call_PushString(prize);
	Call_Finish(result);
	return result == Plugin_Continue;
}

void Forward_OnGiveawayEnded(int creator, int winner, int participants, const char[] prize) {
	Call_StartForward(g_gfOnGiveawayEnded);
	Call_PushCell(creator);
	Call_PushCell(winner);
	Call_PushCell(participants);
	Call_PushString(prize);
	Call_Finish();
}

bool Forward_OnClientEnter(int client) {
	Action result;
	Call_StartForward(g_gfOnClientEnter);
	Call_PushCell(client);
	Call_Finish(result);
	return result == Plugin_Continue;
}

bool Forward_OnClientLeave(int client) {
	Action result;
	Call_StartForward(g_gfOnClientLeave);
	Call_PushCell(client);
	Call_Finish(result);
	return result == Plugin_Continue;
}

bool Forward_OnGiveawayCancel(int creator, int cancelator) {
	Action result;
	Call_StartForward(g_gfOnGiveawayCancel);
	Call_PushCell(creator);
	Call_PushCell(cancelator);
	Call_Finish(result);
	return result == Plugin_Continue;
} 