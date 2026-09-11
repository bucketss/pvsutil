// pvsvis - places locked fake clients around a map and shows which are in your PVS and which are only in your PAS  


#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <file>
#include <message_const>
#include <reapi>
#include <pvsutil>

#define VERSION         "1.0.0"

#define MAX_BOTS        16
#define MAX_PLAYERS     32

#define BOT_PREFIX      "PVS"
#define HUD_INTERVAL    0.2

#define LASER_SPRITE    "sprites/lgtning.spr"

// player 1 = bit 0
#define PlayerBit(%1)   ( 1 << ((%1) - 1) )

new g_iBotOfSlot[MAX_BOTS]
new Float:g_vecSlotOrigin[MAX_BOTS][3]
new Float:g_vecSlotAngles[MAX_BOTS][3]

new g_iSlotOfBot[MAX_PLAYERS + 1]

new bool:g_bHud[MAX_PLAYERS + 1]

new g_iViewSlot[MAX_PLAYERS + 1]

new g_iMaxPlayers
new g_iSprite
new g_pBeams

public plugin_init()
{
	register_plugin("pvsvis", VERSION, "arc")

	g_pBeams = register_cvar("pvsvis_beams", "0")

	register_clcmd("pvs_place",  "CmdPlace",  ADMIN_RCON, "- places a locked bot at your feet")
	register_clcmd("pvs_remove", "CmdRemove", ADMIN_RCON, "[slot] - removes a bot, or the last one placed")
	register_clcmd("pvs_clear",  "CmdClear",  ADMIN_RCON, "- removes every bot")
	register_clcmd("pvs_list",   "CmdList",   ADMIN_RCON, "- lists the placed bots")
	register_clcmd("pvs_save",   "CmdSave",   ADMIN_RCON, "- saves the layout for this map")
	register_clcmd("pvs_load",   "CmdLoad",   ADMIN_RCON, "- loads the layout for this map")
	register_clcmd("pvs_view",   "CmdView",   ADMIN_RCON, "[slot] - views from a bot, or cycles")
	register_clcmd("pvs_hud",    "CmdHud",    ADMIN_RCON, "- toggles the readout")
	register_clcmd("pvs_check",  "CmdCheck",  ADMIN_RCON, "- asserts the native contracts")

	RegisterHookChain(RG_CBasePlayer_Spawn, "Spawn_Post", true)

	g_iMaxPlayers = get_maxplayers()

	set_task(HUD_INTERVAL, "TaskHud", .flags = "b")
}

public plugin_precache()
{
	g_iSprite = precache_model(LASER_SPRITE)
}

public client_disconnected(id)
{
	new iSlot = g_iSlotOfBot[id]

	if (iSlot)
	{
		g_iBotOfSlot[iSlot - 1] = 0
		g_iSlotOfBot[id] = 0
	}

	g_bHud[id] = false
	g_iViewSlot[id] = 0
}

static PlaceBot(iSlot)
{
	new id = g_iBotOfSlot[iSlot]

	if (!id || !is_user_connected(id))
		return

	set_pev(id, pev_movetype, MOVETYPE_NONE)
	set_pev(id, pev_velocity, Float:{ 0.0, 0.0, 0.0 })
	set_pev(id, pev_takedamage, DAMAGE_NO)

	set_pev(id, pev_angles, g_vecSlotAngles[iSlot])
	set_pev(id, pev_v_angle, g_vecSlotAngles[iSlot])
	set_pev(id, pev_fixangle, 1)

	engfunc(EngFunc_SetOrigin, id, g_vecSlotOrigin[iSlot])
}

public Spawn_Post(id)
{
	new iSlot = g_iSlotOfBot[id]

	if (iSlot)
		PlaceBot(iSlot - 1)
}

static CreateBot(iSlot)
{
	new szName[32]
	formatex(szName, charsmax(szName), "%s%02d", BOT_PREFIX, iSlot + 1)

	new id = engfunc(EngFunc_CreateFakeClient, szName)

	if (!id)
		return 0

	new szReject[128]
	dllfunc(DLLFunc_ClientConnect, id, szName, "127.0.0.1", szReject)
	dllfunc(DLLFunc_ClientPutInServer, id)

	g_iBotOfSlot[iSlot] = id
	g_iSlotOfBot[id] = iSlot + 1

	rg_join_team(id, TEAM_CT)
	rg_round_respawn(id)

	PlaceBot(iSlot)

	return id
}

static FreeSlot()
{
	for (new s = 0; s < MAX_BOTS; s++)
	{
		if (!g_iBotOfSlot[s])
			return s
	}

	return -1
}

static RemoveBot(iSlot)
{
	new id = g_iBotOfSlot[iSlot]

	if (!id)
		return

	if (is_user_connected(id))
		server_cmd("kick #%d", get_user_userid(id))

	g_iSlotOfBot[id] = 0
	g_iBotOfSlot[iSlot] = 0
}

public CmdPlace(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new iSlot = FreeSlot()

	if (iSlot == -1)
	{
		client_print(id, print_console, "[pvsvis] all %d slots are full", MAX_BOTS)
		return PLUGIN_HANDLED
	}

	pev(id, pev_origin, g_vecSlotOrigin[iSlot])
	pev(id, pev_angles, g_vecSlotAngles[iSlot])

	g_vecSlotAngles[iSlot][0] = 0.0

	if (!CreateBot(iSlot))
	{
		client_print(id, print_console, "[pvsvis] no free player slot on the server")
		return PLUGIN_HANDLED
	}

	client_print(id, print_console, "[pvsvis] placed %s%02d", BOT_PREFIX, iSlot + 1)

	return PLUGIN_HANDLED
}

public CmdRemove(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new szArg[8]
	read_argv(1, szArg, charsmax(szArg))

	new iSlot = szArg[0] ? (str_to_num(szArg) - 1) : -1

	if (iSlot == -1)
	{
		for (new s = MAX_BOTS - 1; s >= 0; s--)
		{
			if (g_iBotOfSlot[s])
			{
				iSlot = s
				break
			}
		}
	}

	if (iSlot < 0 || iSlot >= MAX_BOTS || !g_iBotOfSlot[iSlot])
	{
		client_print(id, print_console, "[pvsvis] no such bot")
		return PLUGIN_HANDLED
	}

	RemoveBot(iSlot)
	client_print(id, print_console, "[pvsvis] removed %s%02d", BOT_PREFIX, iSlot + 1)

	return PLUGIN_HANDLED
}

public CmdClear(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	for (new s = 0; s < MAX_BOTS; s++)
		RemoveBot(s)

	client_print(id, print_console, "[pvsvis] cleared")

	return PLUGIN_HANDLED
}

public CmdList(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new iCount

	for (new s = 0; s < MAX_BOTS; s++)
	{
		if (!g_iBotOfSlot[s])
			continue

		client_print(id, print_console, "[pvsvis] %s%02d  %.0f %.0f %.0f",
			BOT_PREFIX, s + 1,
			g_vecSlotOrigin[s][0], g_vecSlotOrigin[s][1], g_vecSlotOrigin[s][2])

		iCount++
	}

	client_print(id, print_console, "[pvsvis] %d placed", iCount)

	return PLUGIN_HANDLED
}

static LayoutPath(szPath[], iLen)
{
	new szData[80], szMap[32]

	get_localinfo("amxx_datadir", szData, charsmax(szData))
	get_mapname(szMap, charsmax(szMap))

	formatex(szPath, iLen, "%s/pvsvis_%s.ini", szData, szMap)
}

public CmdSave(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new szPath[128]
	LayoutPath(szPath, charsmax(szPath))

	new f = fopen(szPath, "wt")

	if (!f)
	{
		client_print(id, print_console, "[pvsvis] cannot write %s", szPath)
		return PLUGIN_HANDLED
	}

	new iCount

	for (new s = 0; s < MAX_BOTS; s++)
	{
		if (!g_iBotOfSlot[s])
			continue

		fprintf(f, "%f %f %f %f %f^n",
			g_vecSlotOrigin[s][0], g_vecSlotOrigin[s][1], g_vecSlotOrigin[s][2],
			g_vecSlotAngles[s][1], g_vecSlotAngles[s][2])

		iCount++
	}

	fclose(f)

	client_print(id, print_console, "[pvsvis] saved %d to %s", iCount, szPath)

	return PLUGIN_HANDLED
}

public CmdLoad(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new szPath[128]
	LayoutPath(szPath, charsmax(szPath))

	new f = fopen(szPath, "rt")

	if (!f)
	{
		client_print(id, print_console, "[pvsvis] no layout at %s", szPath)
		return PLUGIN_HANDLED
	}

	for (new s = 0; s < MAX_BOTS; s++)
		RemoveBot(s)

	new szLine[128], szX[16], szY[16], szZ[16], szYaw[16], szRoll[16]
	new iCount

	while (!feof(f) && iCount < MAX_BOTS)
	{
		fgets(f, szLine, charsmax(szLine))
		trim(szLine)

		if (!szLine[0])
			continue

		if (parse(szLine, szX, charsmax(szX), szY, charsmax(szY), szZ, charsmax(szZ),
			szYaw, charsmax(szYaw), szRoll, charsmax(szRoll)) < 5)
			continue

		g_vecSlotOrigin[iCount][0] = str_to_float(szX)
		g_vecSlotOrigin[iCount][1] = str_to_float(szY)
		g_vecSlotOrigin[iCount][2] = str_to_float(szZ)

		g_vecSlotAngles[iCount][0] = 0.0
		g_vecSlotAngles[iCount][1] = str_to_float(szYaw)
		g_vecSlotAngles[iCount][2] = str_to_float(szRoll)

		if (CreateBot(iCount))
			iCount++
	}

	fclose(f)

	client_print(id, print_console, "[pvsvis] loaded %d", iCount)

	return PLUGIN_HANDLED
}

public CmdView(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new szArg[8]
	read_argv(1, szArg, charsmax(szArg))

	if (szArg[0])
	{
		new iSlot = str_to_num(szArg) - 1

		g_iViewSlot[id] = (iSlot >= 0 && iSlot < MAX_BOTS && g_iBotOfSlot[iSlot]) ? (iSlot + 1) : 0
	}
	else
	{
		new iNext = g_iViewSlot[id]

		do
			iNext = (iNext + 1) % (MAX_BOTS + 1)
		while (iNext && !g_iBotOfSlot[iNext - 1])

		g_iViewSlot[id] = iNext
	}

	if (g_iViewSlot[id])
		client_print(id, print_console, "[pvsvis] viewing from %s%02d", BOT_PREFIX, g_iViewSlot[id])
	else
		client_print(id, print_console, "[pvsvis] viewing from self")

	return PLUGIN_HANDLED
}

public CmdHud(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	g_bHud[id] = !g_bHud[id]

	client_print(id, print_console, "[pvsvis] readout %s", g_bHud[id] ? "on" : "off")

	return PLUGIN_HANDLED
}

static ViewOrigin(id, Float:vecOut[3])
{
	new Float:vecOfs[3]

	pev(id, pev_origin, vecOut)
	pev(id, pev_view_ofs, vecOfs)

	vecOut[0] += vecOfs[0]
	vecOut[1] += vecOfs[1]
	vecOut[2] += vecOfs[2]
}

static DrawBeam(id, const Float:vecFrom[3], const Float:vecTo[3])
{
	message_begin(MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, id)
	write_byte(TE_BEAMPOINTS)
	engfunc(EngFunc_WriteCoord, vecFrom[0])
	engfunc(EngFunc_WriteCoord, vecFrom[1])
	engfunc(EngFunc_WriteCoord, vecFrom[2])
	engfunc(EngFunc_WriteCoord, vecTo[0])
	engfunc(EngFunc_WriteCoord, vecTo[1])
	engfunc(EngFunc_WriteCoord, vecTo[2])
	write_short(g_iSprite)
	write_byte(0)		// start frame
	write_byte(0)		// frame rate
	write_byte(3)		// life, tenths
	write_byte(6)		// width
	write_byte(0)		// noise
	write_byte(255)		// r
	write_byte(160)		// g
	write_byte(0)		// b
	write_byte(160)		// brightness
	write_byte(0)		// scroll speed
	message_end()
}

static ShowSets(id)
{
	new iViewEnt = id

	if (g_iViewSlot[id])
	{
		iViewEnt = g_iBotOfSlot[g_iViewSlot[id] - 1]

		if (!iViewEnt)
		{
			g_iViewSlot[id] = 0
			iViewEnt = id
		}
	}

	new Float:vecEye[3]
	ViewOrigin(iViewEnt, vecEye)

	// scoped native for a remote viewpoint
	new iPvs

	if (g_iViewSlot[id])
	{
		iPvs = fatset_players_at(vecEye)
	}
	else
	{
		fatset_pvs(vecEye)
		iPvs = fatset_players()
	}

	fatset_pas(vecEye)

	new iPas = fatset_players()

	new szSeen[64], szHeard[64], szNeither[64]
	new iSeen, iHeard, iNeither, iBroken
	new bool:bBeams = get_pcvar_num(g_pBeams) != 0

	for (new s = 0; s < MAX_BOTS; s++)
	{
		new bot = g_iBotOfSlot[s]

		if (!bot || bot == iViewEnt)
			continue

		new bool:bPvs = (iPvs & PlayerBit(bot)) != 0
		new bool:bPas = (iPas & PlayerBit(bot)) != 0

		if (bPvs && !bPas)
			iBroken++

		if (bPvs)
		{
			format(szSeen, charsmax(szSeen), "%s %02d", szSeen, s + 1)
			iSeen++
		}
		else if (bPas)
		{
			format(szHeard, charsmax(szHeard), "%s %02d", szHeard, s + 1)
			iHeard++

			if (bBeams)
				DrawBeam(id, vecEye, g_vecSlotOrigin[s])
		}
		else
		{
			format(szNeither, charsmax(szNeither), "%s %02d", szNeither, s + 1)
			iNeither++
		}
	}

	new szView[16], szWarn[32]

	if (g_iViewSlot[id])
		formatex(szView, charsmax(szView), "%s%02d", BOT_PREFIX, g_iViewSlot[id])
	else
		copy(szView, charsmax(szView), "self")

	if (iBroken)
		copy(szWarn, charsmax(szWarn), "^n^n!! in PVS but not PAS")

	set_hudmessage(180, 220, 255, 0.02, 0.28, 0, 0.0, HUD_INTERVAL + 0.1, 0.0, 0.0, 3)
	show_hudmessage(id, "pvsvis  view: %s^n^nseen    (%d):%s^nheard   (%d):%s^nneither (%d):%s%s",
		szView,
		iSeen, szSeen,
		iHeard, szHeard,
		iNeither, szNeither,
		szWarn)
}

public TaskHud()
{
	for (new id = 1; id <= g_iMaxPlayers; id++)
	{
		if (g_bHud[id] && is_user_connected(id) && !is_user_bot(id))
			ShowSets(id)
	}
}

static Report(id, const szWhat[], bool:bPass)
{
	client_print(id, print_console, "[pvsvis] %s ... %s", szWhat, bPass ? "PASS" : "FAIL")
}

public CmdCheck(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	new Float:vecEye[3]
	ViewOrigin(id, vecEye)

	fatset_pvs(vecEye)

	new iPvs = fatset_players()

	fatset_pas(vecEye)

	new iPas = fatset_players()
	new iScoped = fatset_players_at(vecEye)

	Report(id, "self is in own PVS",    (iPvs & PlayerBit(id)) != 0)
	Report(id, "PVS is a subset of PAS", (iPvs & ~iPas) == 0)
	Report(id, "scoped equals split",    iScoped == iPvs)

	// set only lives for the frame that built it, so the stale check has to wait
	fatset_pvs(vecEye)
	set_task(0.1, "TaskCheckStale", id)

	return PLUGIN_HANDLED
}

public TaskCheckStale(id)
{
	if (!is_user_connected(id))
		return

	Report(id, "stale set fails open", fatset_visible(id))
}
