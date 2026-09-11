// pvsbench - times pvsutil's natives against tracelines and ReAPI
//
//     pvs_bench [iterations]   default 100000

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <pvsutil>
#include <reapi>

#define VERSION             "1.0.0"

#define DEFAULT_ITERATIONS  100000
#define MIN_ITERATIONS      1000
#define MAX_ITERATIONS      250000

// player 1 = bit 0
#define PlayerBit(%1)       ( 1 << ((%1) - 1) )

new g_iMaxPlayers

new g_iTargets[32]
new Float:g_vecTargetEye[32][3]
new g_iTargetCount

public plugin_init()
{
	register_plugin("pvsbench", VERSION, "arc")

	register_clcmd("pvs_bench", "CmdBench", ADMIN_RCON, "[iterations] - times pvsutil against tracelines")

	g_iMaxPlayers = get_maxplayers()
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

static Float:NsPer(iMs, iCalls)
{
	return float(iMs) * 1000000.0 / float(iCalls)
}

static Report(id, const szWhat[], iMs, iCalls, const szUnit[] = "call")
{
	if (iMs < 0)
		console_print(id, "[pvsbench] %-24s   timer wrapped, run again", szWhat)
	else if (iMs == 0)
		console_print(id, "[pvsbench] %-24s   <1 ms", szWhat)
	else
		console_print(id, "[pvsbench] %-24s %5d ms  %8.1f ns/%s", szWhat, iMs, NsPer(iMs, iCalls), szUnit)
}

static Ratio(id, const szWhat[], iSlowMs, iFastMs)
{
	if (iSlowMs <= 0 || iFastMs <= 0)
		console_print(id, "[pvsbench] %-24s   too fast to compare, raise the iterations", szWhat)
	else
		console_print(id, "[pvsbench] %-24s %8.1fx", szWhat, float(iSlowMs) / float(iFastMs))
}

static BenchBaseline(iIterations)
{
	new t, iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
	{
		is_user_alive(g_iTargets[t])

		if (++t == g_iTargetCount)
			t = 0
	}

	return tickcount() - iStart
}

static BenchTraceline(id, Float:vecEye[3], iIterations)
{
	new t, iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
	{
		engfunc(EngFunc_TraceLine, vecEye, g_vecTargetEye[t], DONT_IGNORE_MONSTERS, id, 0)

		if (++t == g_iTargetCount)
			t = 0
	}

	return tickcount() - iStart
}

static BenchBuild(Float:vecEye[3], iIterations, bool:bAudible)
{
	new iStart = tickcount()

	if (bAudible)
	{
		for (new n = 0; n < iIterations; n++)
			fatset_pas(vecEye)
	}
	else
	{
		for (new n = 0; n < iIterations; n++)
			fatset_pvs(vecEye)
	}

	return tickcount() - iStart
}

static BenchVisible(Float:vecEye[3], iIterations)
{
	fatset_pvs(vecEye)

	new t, iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
	{
		fatset_visible(g_iTargets[t])

		if (++t == g_iTargetCount)
			t = 0
	}

	return tickcount() - iStart
}

static BenchPlayers(Float:vecEye[3], iIterations)
{
	fatset_pvs(vecEye)

	new iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
		fatset_players()

	return tickcount() - iStart
}

static BenchVisibleAt(Float:vecEye[3], iIterations)
{
	new t, iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
	{
		fatset_visible_at(g_iTargets[t], vecEye)

		if (++t == g_iTargetCount)
			t = 0
	}

	return tickcount() - iStart
}

static BenchPlayersAt(Float:vecEye[3], iIterations)
{
	new iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
		fatset_players_at(vecEye)

	return tickcount() - iStart
}

// one viewer checked against every target.

// ReAPI's equivalent of fatset_visible_at, minus the restore: builds a set
// and tests one entity on every call.
static BenchReapi(Float:vecEye[3], iIterations)
{
	new t, iStart = tickcount()

	for (new n = 0; n < iIterations; n++)
	{
		CheckVisibilityInOrigin(g_iTargets[t], vecEye, VisibilityInPVS)

		if (++t == g_iTargetCount)
			t = 0
	}

	return tickcount() - iStart
}

// One sweep = a set at your eye and every target tested against it. ReAPI
// cannot keep a set, so it builds one per target.

static BenchSweepUtil(Float:vecEye[3], iSweeps)
{
	new iStart = tickcount()

	for (new s = 0; s < iSweeps; s++)
	{
		fatset_pvs(vecEye)
		fatset_players()
	}

	return tickcount() - iStart
}

static BenchSweepReapi(Float:vecEye[3], iSweeps)
{
	new iStart = tickcount()

	for (new s = 0; s < iSweeps; s++)
	{
		for (new t = 0; t < g_iTargetCount; t++)
			CheckVisibilityInOrigin(g_iTargets[t], vecEye, VisibilityInPVS)
	}

	return tickcount() - iStart
}

static BenchTraceAll(id, Float:vecEye[3], iPasses)
{
	new iStart = tickcount()

	for (new p = 0; p < iPasses; p++)
	{
		for (new t = 0; t < g_iTargetCount; t++)
			engfunc(EngFunc_TraceLine, vecEye, g_vecTargetEye[t], DONT_IGNORE_MONSTERS, id, 0)
	}

	return tickcount() - iStart
}

static BenchCullThenTrace(id, Float:vecEye[3], iPasses)
{
	new iStart = tickcount()

	for (new p = 0; p < iPasses; p++)
	{
		fatset_pvs(vecEye)

		new iMask = fatset_players()

		for (new t = 0; t < g_iTargetCount; t++)
		{
			if (iMask & PlayerBit(g_iTargets[t]))
				engfunc(EngFunc_TraceLine, vecEye, g_vecTargetEye[t], DONT_IGNORE_MONSTERS, id, 0)
		}
	}

	return tickcount() - iStart
}


public CmdBench(id, iLevel, iCid)
{
	if (!cmd_access(id, iLevel, iCid, 1))
		return PLUGIN_HANDLED

	// loop measures from the caller's eyes
	if (!is_user_connected(id))
	{
		console_print(id, "[pvsbench] run this from a player's console, not the server's")
		return PLUGIN_HANDLED
	}

	new iIterations = DEFAULT_ITERATIONS

	if (read_argc() > 1)
	{
		new szArg[12]
		read_argv(1, szArg, charsmax(szArg))

		iIterations = clamp(str_to_num(szArg), MIN_ITERATIONS, MAX_ITERATIONS)
	}

	g_iTargetCount = 0

	for (new i = 1; i <= g_iMaxPlayers; i++)
	{
		if (i == id || !is_user_alive(i))
			continue

		g_iTargets[g_iTargetCount] = i
		ViewOrigin(i, g_vecTargetEye[g_iTargetCount])
		g_iTargetCount++
	}

	if (!g_iTargetCount)
	{
		console_print(id, "[pvsbench] nobody else alive to test against; place some pvsvis bots")
		return PLUGIN_HANDLED
	}

	new Float:vecEye[3]
	ViewOrigin(id, vecEye)

	fatset_pvs(vecEye)

	new iMask = fatset_players()
	new iInPvs, iInSight

	for (new t = 0; t < g_iTargetCount; t++)
	{
		if (iMask & PlayerBit(g_iTargets[t]))
			iInPvs++

		engfunc(EngFunc_TraceLine, vecEye, g_vecTargetEye[t], DONT_IGNORE_MONSTERS, id, 0)

		if (get_tr2(0, TR_pHit) == g_iTargets[t])
			iInSight++
	}

	new szMap[32]
	get_mapname(szMap, charsmax(szMap))

	console_print(id, "[pvsbench] ----------------------------------------------------")
	console_print(id, "[pvsbench] %s, %d players", szMap, get_playersnum())
	console_print(id, "[pvsbench] %d targets, %d in your PVS, %d in line of sight", g_iTargetCount, iInPvs, iInSight)
	console_print(id, "[pvsbench] %d calls per row", iIterations)
	console_print(id, "[pvsbench] ----------------------------------------------------")

	new iBaseline  = BenchBaseline(iIterations)
	new iTrace     = BenchTraceline(id, vecEye, iIterations)
	new iBuildPvs  = BenchBuild(vecEye, iIterations, false)
	new iBuildPas  = BenchBuild(vecEye, iIterations, true)
	new iVisible   = BenchVisible(vecEye, iIterations)
	new iPlayers   = BenchPlayers(vecEye, iIterations)
	new iVisibleAt = BenchVisibleAt(vecEye, iIterations)
	new iPlayersAt = BenchPlayersAt(vecEye, iIterations)
	new iReapi     = BenchReapi(vecEye, iIterations)

	Report(id, "native call (baseline)", iBaseline, iIterations)
	Report(id, "traceline", iTrace, iIterations)
	Report(id, "fatset_pvs", iBuildPvs, iIterations)
	Report(id, "fatset_pas", iBuildPas, iIterations)
	Report(id, "fatset_visible", iVisible, iIterations)
	Report(id, "fatset_players", iPlayers, iIterations)
	Report(id, "fatset_visible_at", iVisibleAt, iIterations)
	Report(id, "fatset_players_at", iPlayersAt, iIterations)
	Report(id, "CheckVisibilityInOrigin", iReapi, iIterations)

	console_print(id, "[pvsbench] ----------------------------------------------------")

	Ratio(id, "traceline/fatset_visible", iTrace, iVisible)

	new iPasses = max(1, iIterations / g_iTargetCount)

	new iTraceAll = BenchTraceAll(id, vecEye, iPasses)
	new iCulled   = BenchCullThenTrace(id, vecEye, iPasses)

	console_print(id, "[pvsbench] ---- one pass = you against all %d targets, %d passes ----", g_iTargetCount, iPasses)

	Report(id, "trace every target", iTraceAll, iPasses, "pass")
	Report(id, "PVS cull, trace the rest", iCulled, iPasses, "pass")
	Ratio(id, "cull speedup", iTraceAll, iCulled)

	// nothing moves during the command, so every pass skips the same targets
	new iSaved = g_iTargetCount - iInPvs

	console_print(id, "[pvsbench] %-24s %5d of %d per pass, %d total", "traces saved", iSaved, g_iTargetCount, iSaved * iPasses)

	new iSweepUtil  = BenchSweepUtil(vecEye, iPasses)
	new iSweepReapi = BenchSweepReapi(vecEye, iPasses)

	console_print(id, "[pvsbench] ---- one sweep = your PVS against all %d targets, %d sweeps ----", g_iTargetCount, iPasses)

	Report(id, "fatset_pvs + players", iSweepUtil, iPasses, "sweep")
	Report(id, "reapi, one per target", iSweepReapi, iPasses, "sweep")
	Ratio(id, "reapi/pvsutil", iSweepReapi, iSweepUtil)

	return PLUGIN_HANDLED
}
