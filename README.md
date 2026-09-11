# pvsutil

AMXX module that grants access to the engine's fat PVS and PAS functions, `pfnSetFatPVS`/`pfnSetFatPAS`.

this allows cheap lookups for coarse visual culling vs. more expensive tracelines

## Natives

    native bool:fatset_pvs(const Float:vecOrigin[3]);
    native bool:fatset_pas(const Float:vecOrigin[3]);
    native bool:fatset_visible(const entity);
    native fatset_players();
    native bool:fatset_visible_at(const entity, const Float:vecOrigin[3]);
    native fatset_players_at(const Float:vecOrigin[3]);

|                     | set        | tests       | safe in `AddToFullPack` |
| ------------------- | ---------- | ----------- | ----------------------- |
| `fatset_pvs`        | PVS        | —           | no, writes engine's PVS |
| `fatset_pas`        | PAS        | —           | yes                     |
| `fatset_visible`    | last built | one entity  | yes                     |
| `fatset_players`    | last built | all players | yes                     |
| `fatset_visible_at` | PVS        | one entity  | yes                     |
| `fatset_players_at` | PVS        | all players | yes                     |

`fatset_pvs` builds visible set and marks it current, overwriting the engine's—fastest way to get pvs.

`fatset_pas` is the same as above but for the audible set, safe everywhere.

`fatset_visible` tests an entity against whatever the _pas or _pvs builder set to current, returns 1 if no set is current.

`fatset_players` returns a bitmask of player slots, bit 0 = player 1:

    fatset_pas(fSrc)
    new iHeard = fatset_players()
    for (new i = 1; i <= g_iMaxPlayers; i++)
    {
        if (iHeard & (1 << (i - 1)))
            // ...
    }

`fatset_visible_at` gets PVS at an origin, restores engine's set before returning, safe to use in AddToFullPack.

`fatset_players_at` is the player sweep, but scoped the same as above, safe for AddToFullPack.

the `_at` natives build, test and restore in one call, they exist for `AddToFullPack`, and cost an extra BSP travel vs. their counterparts (and leave no set current).

## Lifetime

the engine keeps one fat PVS and one fat PAS in static buffers, and ReGameDLL rebuilds both per client per frame, so a set is only good for the call stack that built it. the module hooks both builders and drops its set when anyone else builds one. 

`MSG_PVS`/`MSG_PAS` sends don't touch the fat buffers

## AddToFullPack

tldr: use the "_at" natives if you need PVS in `AddToFullPack`.

engine hands the PVS from `SetupVisibility` to every `AddToFullPack` call in that client's loop, where `fatset_pvs` eats it.

the `_at` natives put it back by rebuilding from the origin `SetupVisibility` used. 

PAS isn't read in that loop, so `fatset_pas` is safe.

## How it works

state:

    current_set      = null     // the set the testers read
    current_set_time = -1       // game time it was built
    engine_origin    = none     // origin SetupVisibility last built its PVS at

builders:

    fatset_pvs(origin):
        current_set      = engine.SetFatPVS(origin)    // overwrites the engine's PVS buffer
        current_set_time = now
        return current_set != null

    fatset_pas(origin):
        same, with engine.SetFatPAS

testers:

    fatset_visible(ent):
        if current_set is null or current_set_time != now:
            return true                                // no usable set: fail open
        if ent is invalid or free:
            log error; return true                     // bad index: fail open
        return engine.CheckVisibility(ent, current_set)

    fatset_players():
        set = current set if still usable, else null
        mask = 0
        for slot in 1..maxplayers:
            if slot is occupied and (set is null or CheckVisibility(slot, set)):
                mask |= bit(slot)                      // null set means every slot is set
        return mask

scoped pair:

    fatset_visible_at(ent, origin):
        if ent is invalid: log error; return true
        set    = engine.SetFatPVS(origin)              // borrow the engine's buffer
        result = CheckVisibility(ent, set)
        engine.SetFatPVS(engine_origin)                // rebuild what SetupVisibility had
        current_set = null                             // leave nothing current
        return result

    fatset_players_at(origin):
        same, but the test is the fatset_players loop

hooks:

    on engine SetFatPVS/SetFatPAS (anyone calls it):
        current_set = null                             // our pointer may be stale now
        if the call didn't come from us:
            engine_origin = origin                     // remember it for restores

    on map start:
        current_set = null; engine_origin = none

building a PVS depends only on the origin and the map, so replaying `engine_origin` rebuilds the exact buffer `SetupVisibility` made. a guard flag around the module's own builds keeps them from overwriting `engine_origin`.

## Building

Windows (MSVC):

    cmake -B build -A Win32
    cmake --build build --config Release

Linux (GCC, needs `g++-multilib` and `libc6-dev-i386`):

    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build

`PVSUTIL_AMXX_ROOT` (default `../amxmodx`) must point at an amxmodx checkout with its `build_deps/` submodules. MinGW can't parse the HLSDK's `_declspec`.

## Installing

Put `pvsutil_amxx.dll` (Windows) or `pvsutil_amxx_i386.so` (Linux) in `addons/amxmodx/modules/`, add `pvsutil` to `configs/modules.ini`, and copy `include/pvsutil.inc` to `scripting/include/`.
