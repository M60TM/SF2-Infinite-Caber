#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#include <dhooks>
#include <dhooks_gameconf_shim>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

#include <sf2>
#include <cbasenpc>
#include <cbasenpc/util>

static ConVar g_CvarCaberCoolTime;

static bool g_bIsAlreadyRechargeState[MAXPLAYERS + 1] = { false, ... };
static bool g_bCaberIsDetonated[MAXPLAYERS + 1] = { false, ... };

static float g_flCaberRechargeTime[MAXPLAYERS + 1] = { 0.0, ... };

static DynamicHook g_DHookMeleeSmack;

public Plugin myinfo =
{
	name = "[SF2] Infinite Caber",
	author = "Sandy",
	description = "Infinite Caber for Survivor!",
	version = "1.0.1",
	url = ""
}

public void OnPluginStart()
{
	GameData hGameConf = new GameData("sf2.infinite_caber");
	if (hGameConf == null) {
		SetFailState("Failed to load gamedata (sf2.infinite_caber).");
	} else if (!ReadDHooksDefinitions("sf2.infinite_caber"))
	{
		SetFailState("Failed to load gamedata (sf2.infinite_caber).");
	}

	g_DHookMeleeSmack = GetDHooksHookDefinition(hGameConf, "CTFWeaponBaseMelee::Smack");

	ClearDHooksDefinitions();
	delete hGameConf;
	
	g_CvarCaberCoolTime = CreateConVar("sf2_caber_cooltime", "15.0", "caber cooltime. max = 30.0 min = 5.0",
					0, true, 5.0, true, 30.0);
}

public void OnMapStart() {
	PrecacheSound("player/recharged.wav");

	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_weapon_stickbomb")) != -1) {
		if (IsValidEntity(ent) && IsWeaponBaseMelee(ent)) {
			OnMeleeWeaponCreated(ent);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (IsValidEntity(entity) && IsWeaponBaseMelee(entity) && StrEqual(classname, "tf_weapon_stickbomb")) {
		SDKHook(entity, SDKHook_SpawnPost, OnWeaponSpawnPost);
	}
}

void OnWeaponSpawnPost(int weapon) {
	OnMeleeWeaponCreated(weapon);
}

void OnMeleeWeaponCreated(int weapon) {
	g_DHookMeleeSmack.HookEntity(Hook_Pre, weapon, OnStickBombSmackPre);
	g_DHookMeleeSmack.HookEntity(Hook_Post, weapon, OnStickBombSmackPost);
}

public void OnClientPutInServer(int client) {
	g_flCaberRechargeTime[client] = 0.0;
}

MRESReturn OnStickBombSmackPre(int stickbomb)
{
	int owner = GetEntPropEnt(stickbomb, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClient(owner))
	{
		return MRES_Ignored;
	}

	g_bCaberIsDetonated[owner] = !!GetEntProp(stickbomb, Prop_Send, "m_iDetonated");
	
	return MRES_Ignored;
}

MRESReturn OnStickBombSmackPost(int stickbomb)
{
	int owner = GetEntPropEnt(stickbomb, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClient(owner))
	{
		return MRES_Ignored;
	}

	// This means caber is already detonated
	if (g_bCaberIsDetonated[owner])
	{
		return MRES_Ignored;
	}

	// We smacked teammates
	if (!GetEntProp(stickbomb, Prop_Send, "m_iDetonated"))
	{
		return MRES_Ignored;
	}

	g_bCaberIsDetonated[owner] = true;
	
	
	if (!g_bIsAlreadyRechargeState[owner])
	{
		g_flCaberRechargeTime[owner] = GetGameTime() + g_CvarCaberCoolTime.FloatValue;
		SDKHook(owner, SDKHook_PostThinkPost, OnClientPostThinkPost);
		g_bIsAlreadyRechargeState[owner] = true;
	}

	return MRES_Ignored;
}

void OnClientPostThinkPost(int client) {
	if (GetGameTime() >= g_flCaberRechargeTime[client]) {
		g_bIsAlreadyRechargeState[client] = false;
		RechargeCaber(client);
	}
}

void RechargeCaber(int client) {
	if (!IsValidClient(client))
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
		return;
	}

	if (SF2_IsClientEliminated(client) || SF2_DidClientEscape(client))
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
		return;
	}

	int stickbomb = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);

	if (!IsValidEntity(stickbomb))
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
		return;
	}

	if (!HasEntProp(stickbomb, Prop_Send, "m_iDetonated"))
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
		return;
	}

	if (GetEntProp(stickbomb, Prop_Send, "m_iDetonated"))
	{
		SetEntProp(stickbomb, Prop_Send, "m_bBroken", 0);
		SetEntProp(stickbomb, Prop_Send, "m_iDetonated", 0);
		EmitSoundToClient(client, "player/recharged.wav");
	}

	SDKUnhook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

bool IsWeaponBaseMelee(int entity)
{
	return HasEntProp(entity, Prop_Data, "CTFWeaponBaseMeleeSmack");
}

stock bool IsValidClient(int client, bool replaycheck=true)
{
	if(client<=0 || client>MaxClients)
		return false;

	if(!IsClientInGame(client))
		return false;

	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;

	if(replaycheck && (IsClientSourceTV(client) || IsClientReplay(client)))
		return false;

	return true;
}