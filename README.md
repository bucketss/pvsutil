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

`fatset_players` returns a bitmask of player slots, bit 0 = player 1:

    fatset_pas(fSrc)
    new iHeard = fatset_players()
    for (new i = 1; i <= g_iMaxPlayers; i++)
    {
        if (iHeard & (1 << (i - 1)))
            // ...
    }

the `_at` natives build, test and restore in one call, they exist for `AddToFullPack`, and cost an extra BSP travel vs. their counterparts (and leave no set current).

## Lifetime

the engine keeps one fat PVS and one fat PAS in static buffers, and ReGameDLL rebuilds both per client per frame, so a set is only good for the call stack that built it. the module hooks both builders and drops its set when anyone else builds one. 

`MSG_PVS`/`MSG_PAS` sends don't touch the fat buffers

## AddToFullPack

tldr: use the "_at" natives if you need PVS in `AddToFullPack`.

engine hands the PVS from `SetupVisibility` to every `AddToFullPack` call in that client's loop, where `fatset_pvs` eats it.

the `_at` natives put it back by rebuilding from the origin `SetupVisibility` used. 

PAS isn't read in that loop, so `fatset_pas` is safe.

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
