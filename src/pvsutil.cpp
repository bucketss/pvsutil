// pvsutil - exposes the engine's fat visibility sets to AMXX plugins

#include "amxxmodule.h"

static unsigned char *g_pFatSet = NULL;
static float g_flFatSetTime = -1.0f;

enum
{
	kSetVisible = 0,
	kSetAudible = 1,
	kSetCount   = 2
};

static float g_vecEngineOrigin[kSetCount][3];
static bool g_bHaveEngineOrigin[kSetCount];

static bool g_bInBuild = false;

static void InvalidateFatSet()
{
	g_pFatSet = NULL;
	g_flFatSetTime = -1.0f;
}

static inline bool FatSetIsCurrent()
{
	return g_pFatSet != NULL && gpGlobals->time == g_flFatSetTime;
}

static unsigned char *CallSetFat(bool bAudible, const float *pvecOrigin)
{
	g_bInBuild = true;

	unsigned char *pSet = bAudible
		? g_engfuncs.pfnSetFatPAS((float *)pvecOrigin)
		: g_engfuncs.pfnSetFatPVS((float *)pvecOrigin);

	g_bInBuild = false;

	return pSet;
}

static void RestoreEngineSet(bool bAudible)
{
	if (!g_bHaveEngineOrigin[bAudible])
		return;

	CallSetFat(bAudible, g_vecEngineOrigin[bAudible]);
}

static void ReadOrigin(AMX *amx, cell amxOrigin, float *pvecOut)
{
	cell *pOrigin = MF_GetAmxAddr(amx, amxOrigin);

	pvecOut[0] = amx_ctof(pOrigin[0]);
	pvecOut[1] = amx_ctof(pOrigin[1]);
	pvecOut[2] = amx_ctof(pOrigin[2]);
}

static edict_t *EdictForTest(AMX *amx, const char *pszNative, int iEntity)
{
	if (iEntity < 1 || iEntity >= gpGlobals->maxEntities)
	{
		MF_LogError(amx, AMX_ERR_NATIVE, "%s: invalid entity index %d", pszNative, iEntity);
		return NULL;
	}

	edict_t *pEdict = g_engfuncs.pfnPEntityOfEntIndex(iEntity);

	if (pEdict == NULL || pEdict->free)
	{
		MF_LogError(amx, AMX_ERR_NATIVE, "%s: entity %d is not in use", pszNative, iEntity);
		return NULL;
	}

	return pEdict;
}

static inline bool TestVisible(edict_t *pEdict, unsigned char *pSet)
{
	return g_engfuncs.pfnCheckVisibility(pEdict, pSet) != 0;
}

static cell PlayerMask(unsigned char *pSet)
{
	int iMaxPlayers = gpGlobals->maxClients;

	if (iMaxPlayers > 32)
		iMaxPlayers = 32;

	cell iMask = 0;

	for (int i = 1; i <= iMaxPlayers; i++)
	{
		edict_t *pEdict = g_engfuncs.pfnPEntityOfEntIndex(i);

		if (pEdict == NULL || pEdict->free)
			continue;

		if (pSet == NULL || TestVisible(pEdict, pSet))
			iMask |= (1 << (i - 1));
	}

	return iMask;
}

static cell BuildFatSet(AMX *amx, cell *params, bool bAudible)
{
	float vecOrigin[3];
	ReadOrigin(amx, params[1], vecOrigin);

	unsigned char *pSet = CallSetFat(bAudible, vecOrigin);

	g_pFatSet = pSet;
	g_flFatSetTime = gpGlobals->time;

	return pSet != NULL;
}

// native bool:fatset_pvs(const Float:vecOrigin[3]);
static cell AMX_NATIVE_CALL fatset_pvs(AMX *amx, cell *params)
{
	return BuildFatSet(amx, params, false);
}

// native bool:fatset_pas(const Float:vecOrigin[3]);
static cell AMX_NATIVE_CALL fatset_pas(AMX *amx, cell *params)
{
	return BuildFatSet(amx, params, true);
}

// native bool:fatset_visible(const entity);
static cell AMX_NATIVE_CALL fatset_visible(AMX *amx, cell *params)
{
	if (!FatSetIsCurrent())
		return 1;

	edict_t *pEdict = EdictForTest(amx, "fatset_visible", params[1]);

	if (pEdict == NULL)
		return 1;

	return TestVisible(pEdict, g_pFatSet);
}

// native fatset_players();
static cell AMX_NATIVE_CALL fatset_players(AMX *amx, cell *params)
{
	(void)amx;
	(void)params;

	return PlayerMask(FatSetIsCurrent() ? g_pFatSet : NULL);
}

static cell ScopedVisibilityTest(AMX *amx, cell amxOrigin, cell (*pfnTest)(unsigned char *, void *), void *pContext)
{
	float vecOrigin[3];
	ReadOrigin(amx, amxOrigin, vecOrigin);

	unsigned char *pSet = CallSetFat(kSetVisible, vecOrigin);
	cell result = pfnTest(pSet, pContext);

	RestoreEngineSet(kSetVisible);

	InvalidateFatSet();

	return result;
}

static cell TestOneEntity(unsigned char *pSet, void *pContext)
{
	return TestVisible((edict_t *)pContext, pSet);
}

static cell TestPlayers(unsigned char *pSet, void *pContext)
{
	(void)pContext;

	return PlayerMask(pSet);
}

// native bool:fatset_visible_at(const entity, const Float:vecOrigin[3]);
static cell AMX_NATIVE_CALL fatset_visible_at(AMX *amx, cell *params)
{
	edict_t *pEdict = EdictForTest(amx, "fatset_visible_at", params[1]);

	if (pEdict == NULL)
		return 1;

	return ScopedVisibilityTest(amx, params[2], TestOneEntity, pEdict);
}

// native fatset_players_at(const Float:vecOrigin[3]);
static cell AMX_NATIVE_CALL fatset_players_at(AMX *amx, cell *params)
{
	return ScopedVisibilityTest(amx, params[1], TestPlayers, NULL);
}

static AMX_NATIVE_INFO g_Natives[] =
{
	{ "fatset_pvs",        fatset_pvs        },
	{ "fatset_pas",        fatset_pas        },
	{ "fatset_visible",    fatset_visible    },
	{ "fatset_players",    fatset_players    },
	{ "fatset_visible_at", fatset_visible_at },
	{ "fatset_players_at", fatset_players_at },
	{ NULL,                NULL              }
};

void OnAmxxAttach()
{
	MF_AddNatives(g_Natives);
}

void ServerActivate_Post(edict_t *pEdictList, int edictCount, int clientMax)
{
	(void)pEdictList;
	(void)edictCount;
	(void)clientMax;

	InvalidateFatSet();

	g_bHaveEngineOrigin[kSetVisible] = false;
	g_bHaveEngineOrigin[kSetAudible] = false;

	RETURN_META(MRES_IGNORED);
}

static void OnEngineSetBuilt(bool bAudible, const float *org)
{
	InvalidateFatSet();

	if (g_bInBuild || org == NULL)
		return;

	g_vecEngineOrigin[bAudible][0] = org[0];
	g_vecEngineOrigin[bAudible][1] = org[1];
	g_vecEngineOrigin[bAudible][2] = org[2];

	g_bHaveEngineOrigin[bAudible] = true;
}

unsigned char *SetFatPVS_Post(float *org)
{
	OnEngineSetBuilt(kSetVisible, org);

	RETURN_META_VALUE(MRES_IGNORED, NULL);
}

unsigned char *SetFatPAS_Post(float *org)
{
	OnEngineSetBuilt(kSetAudible, org);

	RETURN_META_VALUE(MRES_IGNORED, NULL);
}
