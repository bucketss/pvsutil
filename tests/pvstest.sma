// pvstest - asserts pvsutil's native contracts and prints PASS/FAIL.
//
//     pvs_test           runs the battery
//     pvs_test errors    also feeds the natives bad entity indices, which logs

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <pvsutil>

#define VERSION         "1.0.0"

#define PROBE_DIST      4096.0

// player 1 = bit 0
#define PlayerBit(%1)   ( 1 << ((%1) - 1) )

new g_iPass, g_iFail, g_iSkip
new g_iMaxPlayers

new Float:g_vecBlind[3]
new bool:g_bHaveBlind
new bool:g_bWantErrors

public plugin_init()
{
	register_plugin("pvstest", VERSION, "arc")

	register_clcmd("pvs_test", "CmdTest", ADMIN_RCON, "[errors] - asserts the pvsutil contracts")

	g_iMaxPlayers = get_maxplayers()
}


static Check(id, const szWhat[], bool:bPass)
{
	if (bPass)
		g_iPass++
	else
		g_iFail++

	console_print(id, "[pvstest] %-46s %s", szWhat, bPass ? "PASS" : "FAIL")
}

static Skip(id, const szWhat[], const szWhy[])
{
	g_iSkip++

	console_print(id, "[pvstest] %-46s SKIP  (%s)", szWhat, szWhy)
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

static ConnectedMask()
{
	new iMask

	for (new i = 1; i <= g_iMaxPlayers; i++)
	{
		if (is_user_connected(i))
			iMask |= PlayerBit(i)
	}

	return iMask
}

static bool:FindBlindOrigin(id, Float:vecOut[3])
{
	new const Float:vecProbes[6][3] =
	{
		{  PROBE_DIST,         0.0,         0.0 },
		{ -PROBE_DIST,         0.0,         0.0 },
		{         0.0,  PROBE_DIST,         0.0 },
		{         0.0, -PROBE_DIST,         0.0 },
		{         0.0,         0.0, -PROBE_DIST },
		{         0.0,         0.0,  PROBE_DIST }
	}

	new Float:vecOrigin[3]
	pev(id, pev_origin, vecOrigin)

	for (new p = 0; p < sizeof(vecProbes); p++)
	{
		vecOut[0] = vecOrigin[0] + vecProbes[p][0]
		vecOut[1] = vecOrigin[1] + vecProbes[p][1]
		vecOut[2] = vecOrigin[2] + vecProbes[p][2]

		fatset_pvs(vecOut)

		if (!fatset_visible(id))
			return true
	}

	return false
}

/*************************** the battery ***************************/

public CmdTest(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	// every check builds a set at the caller's eyes
	if (!is_user_connected(id))
	{
		console_print(id, "[pvstest] run this from a player's console, not the server's")
		return PLUGIN_HANDLED
	}

	new szArg[8]
	read_argv(1, szArg, charsmax(szArg))

	g_bWantErrors = (equali(szArg, "errors") != 0)

	g_iPass = 0
	g_iFail = 0
	g_iSkip = 0

	new Float:vecEye[3]
	ViewOrigin(id, vecEye)

	new iConnected = ConnectedMask()

	console_print(id, "[pvstest] ----------------------------------------------------")

	Check(id, "fatset_pvs builds a set", fatset_pvs(vecEye))

	new iPvs = fatset_players()

	Check(id, "you are in your own PVS", fatset_visible(id))
	Check(id, "you are in the PVS player mask", (iPvs & PlayerBit(id)) != 0)

	new iLoop

	for (new i = 1; i <= g_iMaxPlayers; i++)
	{
		if (is_user_connected(i) && fatset_visible(i))
			iLoop |= PlayerBit(i)
	}

	Check(id, "fatset_players equals a fatset_visible loop", iLoop == (iPvs & iConnected))

	Check(id, "fatset_pas builds a set", fatset_pas(vecEye))

	new iPas = fatset_players()

	Check(id, "PVS is a subset of PAS", ((iPvs & ~iPas) & iConnected) == 0)

	new iSeen, iMissing

	for (new i = 1; i <= g_iMaxPlayers; i++)
	{
		if (i == id || !is_user_connected(i) || !is_user_alive(i))
			continue

		new Float:vecTarget[3]
		ViewOrigin(i, vecTarget)

		engfunc(EngFunc_TraceLine, vecEye, vecTarget, DONT_IGNORE_MONSTERS, id, 0)

		if (get_tr2(0, TR_pHit) != i)
			continue

		iSeen++

		if (!(iPvs & PlayerBit(i)))
			iMissing++
	}

	if (iSeen)
		Check(id, "line of sight implies PVS", iMissing == 0)
	else
		Skip(id, "line of sight implies PVS", "nobody else in sight")

	fatset_pvs(vecEye)

	new iSplit = fatset_players()

	Check(id, "fatset_players_at agrees with the split pair", fatset_players_at(vecEye) == iSplit)

	g_bHaveBlind = FindBlindOrigin(id, g_vecBlind)

	if (!g_bHaveBlind)
	{
		Skip(id, "a remote origin can exclude you", "no probe found one")
		Skip(id, "fatset_visible_at agrees with the split pair", "no blind origin")
		Skip(id, "fatset_players_at agrees with the split pair", "no blind origin")
		Skip(id, "fatset_visible fails open after a scoped call", "no blind origin")

		set_task(0.1, "TaskDeferred", id)

		return PLUGIN_HANDLED
	}

	Check(id, "a remote origin can exclude you", true)

	fatset_pvs(g_vecBlind)

	new bool:bSplitOne = fatset_visible(id)
	new iSplitAll = fatset_players()

	Check(id, "fatset_visible_at agrees with the split pair", fatset_visible_at(id, g_vecBlind) == bSplitOne)
	Check(id, "fatset_players_at agrees with the split pair", fatset_players_at(g_vecBlind) == iSplitAll)

	fatset_visible_at(id, g_vecBlind)

	Check(id, "fatset_visible fails open after a scoped call", fatset_visible(id))

	fatset_pvs(g_vecBlind)

	set_task(0.1, "TaskDeferred", id)

	return PLUGIN_HANDLED
}

public TaskDeferred(id)
{
	if (!is_user_connected(id))
		return

	if (g_bHaveBlind)
		Check(id, "a set from an earlier frame fails open", fatset_visible(id))
	else
		Skip(id, "a set from an earlier frame fails open", "no blind origin")

	console_print(id, "[pvstest] ----------------------------------------------------")
	console_print(id, "[pvstest] %d passed, %d failed, %d skipped", g_iPass, g_iFail, g_iSkip)

	if (!g_bWantErrors)
	{
		console_print(id, "[pvstest] run 'pvs_test errors' to also check the bad-index paths")
		return
	}

	console_print(id, "[pvstest] ---- bad indices, errors below are expected ----")

	fatset_pvs(g_vecBlind)

	Check(id, "index 0 fails open", fatset_visible(0))
	Check(id, "an out of range index fails open", fatset_visible(9999))
}
