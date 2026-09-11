#if defined _pvsutil_included
	#endinput
#endif
#define _pvsutil_included

#if AMXX_VERSION_NUM >= 175
	#pragma reqlib pvsutil
	#if !defined AMXMODX_NOAUTOLOAD
		#pragma loadlib pvsutil
	#endif
#else
	#pragma library pvsutil
#endif

/**
 * Builds the engine's fat PVS at an origin.
 *
 * @note The engine keeps one fat set at a time in a static buffer, and
 *       a set is therefore only good for the call stack that built it
 *
 * @param vecOrigin  Point to build the set around
 *
 * @return           true if a set was built
 */
native bool:fatset_pvs(const Float:vecOrigin[3]);

/**
 * Builds the engine's fat PAS at an origin.
 *
 * PAS is a superset of PVS.
 *
 * @param vecOrigin  Point to build the set around
 *
 * @return           true if a set was built
 */
native bool:fatset_pas(const Float:vecOrigin[3]);

/**
 * Tests an entity against the set built by the last fatset_pvs/fatset_pas call.
 *
 * The entity must be linked into the world; the test reads the leaf numbers
 * the engine filled in at link time. Players always qualify.
 *
 * @param entity     Entity index to test
 *
 * @return           true if the entity is in the current set, and also true if
 *                   no set is current, so a missing set shows everything
 *                   rather than nothing
 */
native bool:fatset_visible(const entity);

/**
 * Tests every player slot against the current set at once.
 *
 * The same test fatset_visible() does, over all of them in one call. Bit 0 is
 * player 1, bit 31 is player 32; a slot holding no edict is always clear.
 * Intended for culling a message's recipients:
 *
 *     fatset_pas(fSrc)
 *     new iVisible = fatset_players()
 *     for (new i = 1; i <= g_iMaxPlayers; i++)
 *     {
 *         if (!(iVisible & (1 << (i - 1))))
 *             continue
 *         // ...
 *     }
 *
 * @return           Bitmask of the players in the current set, or of every
 *                   occupied slot if no set is current
 */
native fatset_players();

/**
 * Tests an entity against a PVS built at an origin, in one call.
 *
 * Builds the set, runs the test, and puts the game DLL's set back before
 * returning, so unlike fatset_pvs() this is safe inside AddToFullPack.
 *
 * Costs two BSP descents, one to build and one to restore.
 *
 * fatset_pas() needs no equivalent: the audible set is not read across the
 * AddToFullPack loop.
 *
 * @note Leaves no set current: a following fatset_visible() answers true for
 *       everything until the next fatset_pvs()/fatset_pas().
 *
 * @param entity     Entity index to test
 * @param vecOrigin  Point to build the set around
 *
 * @return           true if the entity is in the set
 */
native bool:fatset_visible_at(const entity, const Float:vecOrigin[3]);

/**
 * Tests every player slot against a PVS built at an origin, in one call.
 *
 * fatset_players() done as a single scoped call. See fatset_visible_at() for
 * the restore behaviour and the cost.
 *
 * @param vecOrigin  Point to build the set around
 *
 * @return           Bitmask of the players in the set, bit 0 being player 1
 */
native fatset_players_at(const Float:vecOrigin[3]);
