#ifndef __MODULECONFIG_H__
#define __MODULECONFIG_H__

#ifndef PVSUTIL_VERSION
#define PVSUTIL_VERSION "0.0.0"
#endif

#define MODULE_NAME     "PVS Util"
#define MODULE_VERSION  PVSUTIL_VERSION
#define MODULE_AUTHOR   "arc"
#define MODULE_URL      ""
#define MODULE_LOGTAG   "PVSUTIL"
#define MODULE_LIBRARY  "pvsutil"
#define MODULE_LIBCLASS ""
#define MODULE_RELOAD_ON_MAPCHANGE

#ifdef __DATE__
#define MODULE_DATE __DATE__
#else
#define MODULE_DATE "Unknown"
#endif

#define USE_METAMOD

#define NO_ALLOC_OVERRIDES

#define FN_AMXX_ATTACH OnAmxxAttach

#ifdef USE_METAMOD
#define FN_ServerActivate_Post ServerActivate_Post

#define FN_SetFatPVS_Post SetFatPVS_Post
#define FN_SetFatPAS_Post SetFatPAS_Post
#endif // USE_METAMOD

#endif // __MODULECONFIG_H__
