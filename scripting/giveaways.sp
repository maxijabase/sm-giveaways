#include <sourcemod>
#include <sdktools>

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
	
	CreateConVar("sm_giveaways_version", PLUGIN_VERSION, "Standard plugin version ConVar. Please don't change me!", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	g_cvPlaySounds = CreateConVar("sm_giveaways_sounds", "1", "Play start, enter, and end sounds.");
	g_cvGiveawayTime = CreateConVar("sm_giveaway_time", "60", "Amount of time before the giveaway entry time stops");
	
	RegAdminCmd("sm_gstart", CMD_CreateGiveaway, ADMFLAG_ROOT);
	RegAdminCmd("sm_gstop", CMD_StopGiveaway, ADMFLAG_ROOT);
	
	RegConsoleCmd("sm_enter", CMD_Enter);
	
	LoadTranslations("giveaways.phrases");
}

public Action CMD_CreateGiveaway(int client, int args) {
	if (g_bActiveGiveaway) {
		ReplyToCommand(client, "¡Ya hay un sorteo en curso!");
		return Plugin_Handled;
	}
	
	g_alParticipants = new ArrayList();
	g_bActiveGiveaway = true;
	PrintCenterTextAll("¡EMPEZÓ UN SORTEO! COMIENZA EN %i SEGUNDOS - ESCRIBÍ !enter PARA PARTICIPAR", g_cvGiveawayTime.FloatValue);
	CreateTimer(g_cvGiveawayTime.FloatValue, TimerEndCallback);
	return Plugin_Handled;
}

public Action TimerEndCallback(Handle timer) {
	CMD_StopGiveaway(0, 0);
	delete timer;
}

public Action CMD_StopGiveaway(int client, int args) {
	int winner = g_alParticipants.Get(GetRandomInt(0, g_alParticipants.Length) - 1);
	int userid = GetClientOfUserId(winner);
	PrintCenterTextAll("¡EL GANADOR ES %N!", userid);
	g_bActiveGiveaway = false;
	delete g_alParticipants;
	return Plugin_Handled;
}

public Action CMD_Enter(int client, int args) {
	if (!g_bActiveGiveaway) {
		ReplyToCommand(client, "¡No hay ningún sorteo en curso al cual entrar!");
	}
	
	int userid = GetClientUserId(client);
	if (g_alParticipants.FindValue(userid) != -1) {
		ReplyToCommand(client, "¡Ya estás participando en este sorteo!");
		return Plugin_Handled;
	}
	
	g_alParticipants.Push(GetClientUserId(client));
	
	ReplyToCommand(client, "¡Entraste al sorteo! ¡Buena suerte!");
	return Plugin_Handled;
} 