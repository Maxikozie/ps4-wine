/* probe_netlog.c: fire-and-forget UDP log lines to the host (scripts/ps4/logs.sh listens).
 * One datagram per line, at most 512 bytes; never blocks, never fails loudly.
 *
 * From: orbis-ports/orbis-compat optional/orbis_netlog.cpp @ 6922a7b (MIT), rewritten in C
 * with the destination baked in at build time (PROBE_NETLOG_HOST / PROBE_NETLOG_PORT).
 *
 * Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "probe_sce.h"

#include <string.h>

#ifndef PROBE_NETLOG_HOST
#error "PROBE_NETLOG_HOST must name the host's IPv4 address (scripts/ps4/build.sh sets it)"
#endif
#ifndef PROBE_NETLOG_PORT
#define PROBE_NETLOG_PORT 18194
#endif

struct netlog_sin
{
    uint8_t  sin_len;
    uint8_t  sin_family;
    uint16_t sin_port;  /* network order */
    uint32_t sin_addr;  /* network order */
    uint8_t  sin_zero[8];
};

static int netlog_sock = -1;
static struct netlog_sin netlog_dst;

int probe_netlog_init(void)
{
    if (netlog_sock >= 0) return 0;
    sceNetInit();
    netlog_sock = sceNetSocket( "ps4wine-probe-log", 2 /* AF_INET */, 2 /* SOCK_DGRAM */, 0 );
    if (netlog_sock < 0)
    {
        int rc = netlog_sock;
        netlog_sock = -1;
        return rc;
    }
    memset( &netlog_dst, 0, sizeof(netlog_dst) );
    netlog_dst.sin_len = sizeof(netlog_dst);
    netlog_dst.sin_family = 2;
    netlog_dst.sin_port = sceNetHtons( PROBE_NETLOG_PORT );
    if (sceNetInetPton( 2, PROBE_NETLOG_HOST, &netlog_dst.sin_addr ) != 1)
    {
        sceNetSocketClose( netlog_sock );
        netlog_sock = -1;
        return -1;
    }
    return 0;
}

void probe_netlog_send( const char *line, size_t len )
{
    if (netlog_sock < 0) return;
    if (len > 512) len = 512;
    sceNetSendto( netlog_sock, line, len, 0, &netlog_dst, sizeof(netlog_dst) );
}
