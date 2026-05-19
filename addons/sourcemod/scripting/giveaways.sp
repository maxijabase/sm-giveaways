#include <sourcemod>
#include <sdktools>
#include <autoexecconfig>
#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0.1"
#define HUD_DISPLAY_TIME 15.0
#define HUD_FADE_IN 0.1
#define HUD_FADE_OUT 0.2
#define PRIZE_MAX 128

#define UPDATE_URL "https://raw.githubusercontent.com/maxijabase/sm-giveaways/master/updatefile.txt"

#undef REQUIRE_PLUGIN 
#include <updater>

ConVar g_cvPlaySounds;
ConVar g_cvGiveawayTime;
ConVar g_cvWinnerCooldown;
ConVar g_cvCountdown;
ConVar g_cvSendMenuToWinner;
ConVar g_cvHudX;
ConVar g_cvHudY;
ConVar g_cvHudR;
ConVar g_cvHudG;
ConVar g_cvHudB;
ConVar g_cvHudA;

Handle g_hHudSync;

GlobalForward g_gfOnGiveawayStart;
GlobalForward g_gfOnGiveawayEnded;
GlobalForward g_gfOnClientEnter;
GlobalForward g_gfOnClientLeave;
GlobalForward g_gfOnGiveawayCancel;

bool g_bActiveGiveaway = false;
bool g_bSuspensePlayed = false;
int g_iCountdownInterval;
int g_iGiveawayCreator;
ArrayList g_alPrizes;
int g_iWinnersWanted = 1;
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
  
  return APLRes_Success;
}

public void OnPluginStart() {
  AutoExecConfig_SetCreateFile(true);
  AutoExecConfig_SetFile("giveaways");
  
  CreateConVar("sm_giveaways_version", PLUGIN_VERSION, "Standard plugin version ConVar. Please don't change me!", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
  
  g_cvPlaySounds = AutoExecConfig_CreateConVar("sm_giveaways_sounds", "1", "Play start, enter, and end sounds.");
  g_cvGiveawayTime = AutoExecConfig_CreateConVar("sm_giveaways_time", "60", "Amount of time before the giveaway entry time stops");
  g_cvWinnerCooldown = AutoExecConfig_CreateConVar("sm_giveaways_winner_cooldown", "1", "Amount of giveaways that must pass before someone that has won, can win again.");
  g_cvCountdown = AutoExecConfig_CreateConVar("sm_giveaways_countdown", "1", "Enable 5 second countdown in HUD and chat.");
  g_cvSendMenuToWinner = AutoExecConfig_CreateConVar("sm_giveaways_winner_sendmenu", "1", "Send an in-game menu (panel) to the winner with customizable details.");
  
  g_cvHudX = AutoExecConfig_CreateConVar("sm_giveaways_hud_x", "-1.0", "X position for HUD messages (-1.0 = center)");
  g_cvHudY = AutoExecConfig_CreateConVar("sm_giveaways_hud_y", "0.25", "Y position for HUD messages");
  g_cvHudR = AutoExecConfig_CreateConVar("sm_giveaways_hud_r", "0", "Red color component for HUD (0-255)");
  g_cvHudG = AutoExecConfig_CreateConVar("sm_giveaways_hud_g", "255", "Green color component for HUD (0-255)");
  g_cvHudB = AutoExecConfig_CreateConVar("sm_giveaways_hud_b", "0", "Blue color component for HUD (0-255)");
  g_cvHudA = AutoExecConfig_CreateConVar("sm_giveaways_hud_a", "255", "Alpha/transparency for HUD (0-255)");
  
  RegAdminCmd("sm_gstart", CMD_CreateGiveaway, ADMFLAG_GENERIC, "Starts a giveaway");
  RegAdminCmd("sm_gstart_now", CMD_CreateGiveawayConfirmed, ADMFLAG_GENERIC, "Internal: start giveaway with pre-confirmed args (bot wizard)");
  RegAdminCmd("sm_gstop", CMD_StopGiveaway, ADMFLAG_GENERIC, "Stops the current giveaway");
  RegAdminCmd("sm_gcancel", CMD_CancelGiveaway, ADMFLAG_GENERIC, "Cancels the current giveaway");
  RegAdminCmd("sm_gparticipants", CMD_Participants, ADMFLAG_GENERIC, "Shows the participants of the current giveaway.");
  
  RegConsoleCmd("sm_enter", CMD_Enter, "Enter the giveaway!");
  RegConsoleCmd("sm_entre", CMD_Enter, "Enter the giveaway!");
  RegConsoleCmd("sm_entrar", CMD_Enter, "Enter the giveaway!");
  RegConsoleCmd("sm_leave", CMD_Leave, "Leave the giveaway!");
  
  g_alPrizes = new ArrayList(ByteCountToCells(PRIZE_MAX + 1));
  g_alParticipants = new ArrayList();
  g_smPastWinners = new StringMap();
  g_hHudSync = CreateHudSynchronizer();
  
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
  g_alPrizes.Clear();
  g_iWinnersWanted = 1;
}

public Action CMD_CreateGiveaway(int client, int args) {
  if (g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayInProgress", client);
    return Plugin_Handled;
  }
  
  char argStr[512];
  GetCmdArgString(argStr, sizeof(argStr));
  TrimString(argStr);
  
  if (!Forward_OnGiveawayStart(client, argStr)) {
    return Plugin_Handled;
  }
  
  if (args == 0) {
    MC_ReplyToCommand(client, "%T", "GiveawayUsageHint", client);
    return Plugin_Handled;
  }
  
  if (!ParseAndSetGiveawayPrizes(client, args)) {
    return Plugin_Handled;
  }
  
  ShowGiveawayConfirmPanel(client);
  return Plugin_Handled;
}

public Action CMD_CreateGiveawayConfirmed(int client, int args) {
  if (g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayInProgress", client);
    return Plugin_Handled;
  }
  
  if (args == 0) {
    MC_ReplyToCommand(client, "%T", "GiveawayUsageHint", client);
    return Plugin_Handled;
  }
  
  if (!ParseAndSetGiveawayPrizes(client, args)) {
    return Plugin_Handled;
  }
  
  BeginGiveawayTimer(client);
  return Plugin_Handled;
}

public Action Timer_CountdownCallback(Handle timer) {
  if (!g_bActiveGiveaway) {
    return Plugin_Stop;
  }
  
  if (g_iCountdownInterval == 0) {
    CMD_StopGiveaway(0, 0);
    return Plugin_Stop;
  }
  
  SetupHudParams();
  
  if (g_iCountdownInterval <= 5) {
    if (!g_bSuspensePlayed) {
      PlaySound("giveaway_suspense.wav");
      g_bSuspensePlayed = true;
    }
    
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char hudMsg[256];
      Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayCountdown_Center", i, g_iCountdownInterval);
      ShowSyncHudText(i, g_hHudSync, hudMsg);
    }
    
    if (g_cvCountdown.BoolValue) {
      for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        char chatMsg[512];
        Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayCountdown_Chat", i, g_iCountdownInterval);
        MC_PrintToChat(i, "%s", chatMsg);
      }
    }
  }
  else {
    bool hasPrize = g_alPrizes.Length > 0;
    bool isMulti = g_alPrizes.Length > 1;
    
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char hudMsg[256];
      if (!hasPrize) {
        Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayStarting_Center", i, g_iCountdownInterval);
      }
      else if (!isMulti) {
        char prize[PRIZE_MAX + 1];
        g_alPrizes.GetString(0, prize, sizeof(prize));
        Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayStarting_Center_Prize", i, prize, g_iCountdownInterval);
      }
      else {
        Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayStarting_Center_Multi", i, g_alPrizes.Length, g_iCountdownInterval);
      }
      ShowSyncHudText(i, g_hHudSync, hudMsg);
    }
  }
  
  g_iCountdownInterval--;
  return Plugin_Continue;
}

public Action CMD_StopGiveaway(int client, int args) {
  if (!g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayNone", client);
    return Plugin_Handled;
  }
  
  FilterParticipants();
  
  if (g_alParticipants.Length == 0) {
    SetupHudParams();
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char hudMsg[256];
      Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayNoWinners_Center", i);
      ShowSyncHudText(i, g_hHudSync, hudMsg);
    }
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char chatMsg[512];
      Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayNoWinners_Chat", i);
      MC_PrintToChat(i, "%s", chatMsg);
    }
    PlaySound("giveaway_canceled.wav");
  }
  else {
    int effectiveN = (g_iWinnersWanted < g_alParticipants.Length) ? g_iWinnersWanted : g_alParticipants.Length;
    
    ArrayList winners = new ArrayList();
    ArrayList pool = g_alParticipants.Clone();
    while (winners.Length < effectiveN && pool.Length > 0) {
      int idx = GetRandomInt(0, pool.Length - 1);
      int uid = pool.Get(idx);
      pool.Erase(idx);
      int cl = GetClientOfUserId(uid);
      if (cl != 0) {
        winners.Push(cl);
      }
    }
    delete pool;
    effectiveN = winners.Length;
    
    // Fisher-Yates shuffle of prizes
    for (int i = g_alPrizes.Length - 1; i > 0; i--) {
      int j = GetRandomInt(0, i);
      char tmp1[PRIZE_MAX + 1], tmp2[PRIZE_MAX + 1];
      g_alPrizes.GetString(i, tmp1, sizeof(tmp1));
      g_alPrizes.GetString(j, tmp2, sizeof(tmp2));
      g_alPrizes.SetString(i, tmp2);
      g_alPrizes.SetString(j, tmp1);
    }
    
    int creator = GetClientOfUserId(g_iGiveawayCreator);
    int totalParticipants = g_alParticipants.Length;
    
    if (effectiveN == 1) {
      int winner = winners.Get(0);
      char prize[PRIZE_MAX + 1];
      bool hasPrize = g_alPrizes.Length > 0;
      if (hasPrize) {
        g_alPrizes.GetString(0, prize, sizeof(prize));
      }
      
      SetupHudParams();
      for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        char hudMsg[256];
        if (hasPrize) {
          Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayWinnerAnnouncement_Center", i, winner, prize);
        }
        else {
          Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayWinnerAnnouncement_Center_NoPrize", i, winner);
        }
        ShowSyncHudText(i, g_hHudSync, hudMsg);
      }
      for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        char chatMsg[512];
        if (hasPrize) {
          Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayWinnerAnnouncement_Chat", i, winner, prize);
        }
        else {
          Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayWinnerAnnouncement_Chat_NoPrize", i, winner);
        }
        MC_PrintToChat(i, "%s", chatMsg);
      }
      
      char steamid[32];
      GetClientAuthId(winner, AuthId_Steam2, steamid, sizeof(steamid));
      g_smPastWinners.SetValue(steamid, 0);
      
      Forward_OnGiveawayEnded(creator, winner, totalParticipants, prize);
      
      if (g_cvSendMenuToWinner.BoolValue) {
        SendWinnerMenu(winner, prize);
      }
    }
    else {
      SetupHudParams();
      for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        char hudMsg[256];
        Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayWinnerAnnouncement_Center_Multi", i, effectiveN);
        ShowSyncHudText(i, g_hHudSync, hudMsg);
      }
      for (int i = 1; i <= MaxClients; i++) {
        if (!IsClientInGame(i) || IsFakeClient(i)) continue;
        char chatMsg[512];
        Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayWinnerAnnouncement_Chat_Multi_Header", i, effectiveN);
        MC_PrintToChat(i, "%s", chatMsg);
      }
      
      for (int w = 0; w < effectiveN; w++) {
        int winner = winners.Get(w);
        char prize[PRIZE_MAX + 1];
        bool hasPrize = w < g_alPrizes.Length;
        if (hasPrize) {
          g_alPrizes.GetString(w, prize, sizeof(prize));
        }
        
        for (int i = 1; i <= MaxClients; i++) {
          if (!IsClientInGame(i) || IsFakeClient(i)) continue;
          char chatLine[512];
          Format(chatLine, sizeof(chatLine), "%T", "GiveawayWinnerAnnouncement_Chat_Multi_Line", i, winner, prize);
          MC_PrintToChat(i, "%s", chatLine);
        }
        
        char steamid[32];
        GetClientAuthId(winner, AuthId_Steam2, steamid, sizeof(steamid));
        g_smPastWinners.SetValue(steamid, 0);
        
        Forward_OnGiveawayEnded(creator, winner, totalParticipants, prize);
        
        if (g_cvSendMenuToWinner.BoolValue) {
          SendWinnerMenu(winner, prize);
        }
      }
    }
    
    PlaySound("giveaway_end.wav");
    delete winners;
  }
  
  AdvanceCooldowns();
  
  g_bActiveGiveaway = false;
  g_alParticipants.Clear();
  g_iGiveawayCreator = 0;
  g_alPrizes.Clear();
  g_iWinnersWanted = 1;
  
  return Plugin_Handled;
}

public Action CMD_CancelGiveaway(int client, int args) {
  if (!Forward_OnGiveawayCancel(GetClientOfUserId(g_iGiveawayCreator), client)) {
    return Plugin_Handled;
  }
  
  if (!g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayNone", client);
    return Plugin_Handled;
  }
  
  g_bActiveGiveaway = false;
  g_alParticipants.Clear();
  g_iGiveawayCreator = 0;
  g_alPrizes.Clear();
  g_iWinnersWanted = 1;
  
  SetupHudParams();
  for (int i = 1; i <= MaxClients; i++) {
    if (!IsClientInGame(i) || IsFakeClient(i)) continue;
    char hudMsg[256];
    Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayCanceled_Center", i);
    ShowSyncHudText(i, g_hHudSync, hudMsg);
  }
  for (int i = 1; i <= MaxClients; i++) {
    if (!IsClientInGame(i) || IsFakeClient(i)) continue;
    char chatMsg[512];
    Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayCanceled_Chat", i);
    MC_PrintToChat(i, "%s", chatMsg);
  }
  
  PlaySound("giveaway_canceled.wav");
  
  return Plugin_Handled;
}

public Action CMD_Enter(int client, int args) {
  if (!Forward_OnClientEnter(client)) {
    return Plugin_Handled;
  }
  
  if (!g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayNone", client);
    return Plugin_Handled;
  }
  
  int userid = GetClientUserId(client);
  if (g_alParticipants.FindValue(userid) != -1) {
    MC_ReplyToCommand(client, "%T", "GiveawayAlreadyParticipating", client);
    return Plugin_Handled;
  }
  
  g_alParticipants.Push(userid);
  MC_ReplyToCommand(client, "%T", "GiveawayEntered", client);
  PlaySound("giveaway_entered.wav", client);
  
  return Plugin_Handled;
}

public Action CMD_Leave(int client, int args) {
  if (!Forward_OnClientLeave(client)) {
    return Plugin_Handled;
  }
  
  if (!g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayNone", client);
    return Plugin_Handled;
  }
  
  int participant = g_alParticipants.FindValue(GetClientUserId(client));
  
  if (participant == -1) {
    MC_ReplyToCommand(client, "%T", "GiveawayNotParticipating", client);
    return Plugin_Handled;
  }
  
  g_alParticipants.Erase(participant);
  PlaySound("giveaway_canceled.wav", client);
  MC_ReplyToCommand(client, "%T", "GiveawayLeft", client);
  return Plugin_Handled;
}

public Action CMD_Participants(int client, int args) {
  if (!g_bActiveGiveaway) {
    MC_ReplyToCommand(client, "%T", "GiveawayNone", client);
    return Plugin_Handled;
  }
  
  int participants = g_alParticipants.Length;
  
  if (participants == 0) {
    MC_ReplyToCommand(client, "%T", "GiveawayNoParticipants", client);
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

public int EmptyMenu(Menu menu, MenuAction action, int param1, int param2) { return 0; }

public int ConfirmPanelHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    if (param2 == 1) {
      BeginGiveawayTimer(param1);
    }
    else {
      g_alPrizes.Clear();
      g_iWinnersWanted = 1;
    }
  }
  else if (action == MenuAction_Cancel) {
    g_alPrizes.Clear();
    g_iWinnersWanted = 1;
  }
  return 0;
}

void PlaySound(char[] sound, int client = 0) {
  if (g_cvPlaySounds.BoolValue) {
    client ? EmitSoundToClient(client, sound) : EmitSoundToAll(sound);
  }
}

void SetupHudParams() {
  SetHudTextParams(
    g_cvHudX.FloatValue, g_cvHudY.FloatValue,
    HUD_DISPLAY_TIME,
    g_cvHudR.IntValue, g_cvHudG.IntValue, g_cvHudB.IntValue, g_cvHudA.IntValue,
    1, HUD_FADE_IN, 0.0, HUD_FADE_OUT
  );
}

bool IsIntegerString(const char[] s) {
  if (s[0] == '\0') return false;
  for (int i = 0; s[i] != '\0'; i++) {
    if (s[i] < '0' || s[i] > '9') return false;
  }
  return true;
}

int CountHumans() {
  int n = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientReplay(i) && !IsClientSourceTV(i)) {
      n++;
    }
  }
  return n;
}

bool ParseAndSetGiveawayPrizes(int client, int args) {
  char firstArg[64];
  GetCmdArg(1, firstArg, sizeof(firstArg));
  
  if (IsIntegerString(firstArg)) {
    int numWinners = StringToInt(firstArg);
    if (numWinners <= 0) {
      MC_ReplyToCommand(client, "%T", "GiveawayUsageHint", client);
      return false;
    }
    int remainingArgs = args - 1;
    if (remainingArgs != numWinners) {
      MC_ReplyToCommand(client, "%T", "GiveawayArgsMismatch", client, numWinners, remainingArgs);
      return false;
    }
    int humans = CountHumans();
    if (numWinners > humans) {
      MC_ReplyToCommand(client, "%T", "GiveawayTooManyWinners", client, numWinners, humans);
      return false;
    }
    
    g_alPrizes.Clear();
    for (int i = 2; i <= args; i++) {
      char prize[PRIZE_MAX + 1];
      GetCmdArg(i, prize, sizeof(prize));
      g_alPrizes.PushString(prize);
    }
    g_iWinnersWanted = numWinners;
  }
  else {
    char argStr[512];
    GetCmdArgString(argStr, sizeof(argStr));
    TrimString(argStr);
    g_alPrizes.Clear();
    if (argStr[0] != '\0') {
      char prize[PRIZE_MAX + 1];
      strcopy(prize, sizeof(prize), argStr);
      g_alPrizes.PushString(prize);
    }
    g_iWinnersWanted = 1;
  }
  
  return true;
}

void BeginGiveawayTimer(int client) {
  if (g_bActiveGiveaway) {
    MC_PrintToChat(client, "%T", "GiveawayInProgress", client);
    g_alPrizes.Clear();
    g_iWinnersWanted = 1;
    return;
  }
  
  int time = g_cvGiveawayTime.IntValue;
  
  g_bActiveGiveaway = true;
  g_bSuspensePlayed = false;
  g_iGiveawayCreator = GetClientUserId(client);
  
  bool hasPrize = g_alPrizes.Length > 0;
  bool isMulti = g_alPrizes.Length > 1;
  
  SetupHudParams();
  
  if (!hasPrize) {
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char hudMsg[256];
      Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayStarting_Center", i, time);
      ShowSyncHudText(i, g_hHudSync, hudMsg);
    }
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char chatMsg[512];
      Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayStarting_Chat", i, time);
      MC_PrintToChat(i, "%s", chatMsg);
    }
  }
  else if (!isMulti) {
    char prize[PRIZE_MAX + 1];
    g_alPrizes.GetString(0, prize, sizeof(prize));
    
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char hudMsg[256];
      Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayStarting_Center_Prize", i, prize, time);
      ShowSyncHudText(i, g_hHudSync, hudMsg);
    }
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char chatMsg[512];
      Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayStarting_Chat_Prize", i, prize, time);
      MC_PrintToChat(i, "%s", chatMsg);
    }
  }
  else {
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char hudMsg[256];
      Format(hudMsg, sizeof(hudMsg), "%T", "GiveawayStarting_Center_Multi", i, g_alPrizes.Length, time);
      ShowSyncHudText(i, g_hHudSync, hudMsg);
    }
    for (int i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i)) continue;
      char chatMsg[512];
      Format(chatMsg, sizeof(chatMsg), "%T", "GiveawayStarting_Chat_Multi", i, g_alPrizes.Length, time);
      MC_PrintToChat(i, "%s", chatMsg);
      for (int p = 0; p < g_alPrizes.Length; p++) {
        char prize[PRIZE_MAX + 1];
        g_alPrizes.GetString(p, prize, sizeof(prize));
        char prizeLine[192];
        Format(prizeLine, sizeof(prizeLine), "%T", "GiveawayStarting_Chat_PrizeLine", i, p + 1, prize);
        MC_PrintToChat(i, "%s", prizeLine);
      }
    }
  }
  
  PlaySound("giveaway_starting.wav");
  
  g_iCountdownInterval = time;
  CreateTimer(1.0, Timer_CountdownCallback, _, TIMER_REPEAT);
}

void ShowGiveawayConfirmPanel(int client) {
  Panel panel = new Panel();
  
  char title[128];
  Format(title, sizeof(title), "%T", "GiveawayConfirmPanel_Title", client);
  panel.SetTitle(title);
  
  char winnersLine[128];
  Format(winnersLine, sizeof(winnersLine), "%T", "GiveawayConfirmPanel_Winners", client, g_iWinnersWanted);
  panel.DrawText(winnersLine);
  
  char prizesHeader[128];
  Format(prizesHeader, sizeof(prizesHeader), "%T", "GiveawayConfirmPanel_PrizesHeader", client);
  panel.DrawText(prizesHeader);
  
  for (int i = 0; i < g_alPrizes.Length; i++) {
    char prize[PRIZE_MAX + 1];
    g_alPrizes.GetString(i, prize, sizeof(prize));
    char prizeLine[140];
    Format(prizeLine, sizeof(prizeLine), "  %d. %s", i + 1, prize);
    panel.DrawText(prizeLine);
  }
  
  panel.DrawText(" ");
  
  char launchStr[64];
  Format(launchStr, sizeof(launchStr), "%T", "GiveawayConfirmPanel_Launch", client);
  char cancelStr[64];
  Format(cancelStr, sizeof(cancelStr), "%T", "GiveawayConfirmPanel_Cancel", client);
  
  panel.DrawItem(launchStr);
  panel.DrawItem(cancelStr);
  
  panel.Send(client, ConfirmPanelHandler, MENU_TIME_FOREVER);
  delete panel;
}

void SendWinnerMenu(int client, const char[] prize) {
  Panel panel = new Panel();
  char panelTitle[64], panelBody[512], exitString[32];
  Format(panelTitle, sizeof(panelTitle), "%T", "GiveawayWinner_MenuTitle", client);
  if (prize[0] == '\0') {
    Format(panelBody, sizeof(panelBody), "%T", "GiveawayWinner_MenuBody_NoPrize", client, client);
  }
  else {
    Format(panelBody, sizeof(panelBody), "%T", "GiveawayWinner_MenuBody", client, client, prize);
  }
  Format(exitString, sizeof(exitString), "%T", "Exit", client);
  panel.SetTitle(panelTitle);
  panel.DrawText(" ");
  panel.DrawText(panelBody);
  panel.DrawText(" ");
  panel.CurrentKey = 10;
  panel.DrawItem(exitString);
  panel.Send(client, EmptyMenu, MENU_TIME_FOREVER);
  delete panel;
}

void AdvanceCooldowns() {
  StringMapSnapshot snapshot = g_smPastWinners.Snapshot();
  for (int i = 0; i < snapshot.Length; i++) {
    int bufferSize = snapshot.KeyBufferSize(i);
    char[] key = new char[bufferSize];
    snapshot.GetKey(i, key, bufferSize);
    
    int value;
    g_smPastWinners.GetValue(key, value);
    
    int next = value + 1;
    
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
    int cl = GetClientOfUserId(g_alParticipants.Get(i));
    if (!CanParticipate(cl)) {
      g_alParticipants.Erase(i);
    }
  }
}

bool CanParticipate(int client) {
  char steamid[32];
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  
  int passed;
  if (g_smPastWinners.GetValue(steamid, passed)) {
    return passed >= g_cvWinnerCooldown.IntValue;
  }
  
  return true;
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
