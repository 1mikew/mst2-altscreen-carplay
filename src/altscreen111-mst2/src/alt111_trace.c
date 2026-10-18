/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * alt111_trace: a SAFE tap on the mdev messages SAL sends.
 *
 * Purpose: capture the START of a stream on an mdev connection -- above all the decoder
 * initialisation, without which the engine rejects our Type-111 push with error::5 even
 * when SPS/PPS/IDR are sent in band. See docs/PROTOCOL-MDEVPUSH.md.
 *
 * LESSON FROM THE PREVIOUS VERSION (it took the unit down): logging to a FILE on every
 * message (fopen/fprintf/fclose) on SAL's hot IPC path delayed it enough for the watchdog
 * to fire. Hence:
 *   - filter by COID: mdev is a name_open connection => (coid & 0x40000000). This
 *     excludes ordinary IPC regardless of message size.
 *   - write into a STATIC IN-MEMORY BUFFER (snprintf only, no syscalls).
 *   - the file is written ONCE, when the buffer is full or /tmp/cpvc_dump appears;
 *     the flag is only checked every 4096 calls.
 *   - only the first TR_MAX messages are kept -- the start of the stream is what matters.
 */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <stdint.h>

struct _tr_iov { void *base; size_t len; };   /* shodne s QNX iov_t */

#define TR_FLAG "/tmp/cpvc_trace"
#define TR_DUMP "/tmp/cpvc_dump"
#define TR_LOG  "/tmp/cpvc_trace.log"
#define TR_BUF  (48*1024)
#define TR_MAX  120
#define TR_HEX  80          /* kolik bajtu z kazde casti vypsat */

static char tr_buf[TR_BUF];
static size_t tr_used;
static int tr_cnt, tr_on, tr_dumped;
static unsigned tr_tick;
static pthread_mutex_t tr_lock = PTHREAD_MUTEX_INITIALIZER;

/* Entirely userspace, no syscalls. Called only for the first TR_MAX mdev messages. */
static void tr_app(const char *fmt, ...)
{
    va_list ap;
    int n;
    if (tr_used + 256 > TR_BUF) return;
    va_start(ap, fmt);
    n = vsnprintf(tr_buf + tr_used, TR_BUF - tr_used, fmt, ap);
    va_end(ap);
    if (n > 0) tr_used += (size_t)n;
}

static void tr_hexapp(const unsigned char *p, size_t n)
{
    size_t i;
    if (n > TR_HEX) n = TR_HEX;
    if (tr_used + n * 2 + 8 > TR_BUF) return;
    for (i = 0; i < n; i++) {
        static const char h[] = "0123456789abcdef";
        tr_buf[tr_used++] = h[p[i] >> 4];
        tr_buf[tr_used++] = h[p[i] & 15];
    }
}

/* one-shot flush of the buffer to disk */
static void tr_flush(void)
{
    FILE *f;
    if (tr_dumped || !tr_used) return;
    tr_dumped = 1;
    f = fopen(TR_LOG, "w");
    if (!f) return;
    fwrite(tr_buf, 1, tr_used, f);
    fclose(f);
}

/* cheap periodic state check (once every 4096 calls) */
static int tr_enabled(void)
{
    if ((tr_tick++ & 0xfff) == 0) {
        tr_on = (access(TR_FLAG, 0) == 0);
        if (access(TR_DUMP, 0) == 0) {
            pthread_mutex_lock(&tr_lock);
            tr_flush();
            pthread_mutex_unlock(&tr_lock);
        }
    }
    return tr_on;
}

/* we only care about mdev: a name_open connection has the top bit set */
static int tr_is_mdev(int coid) { return (coid & 0x40000000) != 0; }

/* Data messages (code==0) are a flood and we already know what they look like. What we
  * need is the opposite: control messages (code != 0) and the first few messages on each
  * new coid, where the start of the stream is. The coid table is small and fixed, no
  * allocation. */
static struct { int coid; int n; } tr_seen[8];

static int tr_first_on_coid(int coid)
{
    int i;
    for (i = 0; i < 8; i++) {
        if (tr_seen[i].coid == coid) return (++tr_seen[i].n) <= 12;
        if (tr_seen[i].coid == 0) { tr_seen[i].coid = coid; tr_seen[i].n = 1; return 1; }
    }
    return 0;
}

/* in the 24-byte header u16@0 is the message code; 0 = data (not interesting) */
static int tr_want_iov(int coid, const struct _tr_iov *iov, int parts)
{
    unsigned code = 0, sub = 3;
    const unsigned char *h;
    if (parts > 0 && iov[0].base && iov[0].len >= 2) {
        h = (const unsigned char *)iov[0].base;
        code = (unsigned)h[0] | ((unsigned)h[1] << 8);
        if (iov[0].len >= 24)
            sub = (unsigned)h[0x10] | ((unsigned)h[0x11] << 8) |
                  ((unsigned)h[0x12] << 16) | ((unsigned)h[0x13] << 24);
    }
    if (code != 0) return 1;                  /* control message (0x100 = connect) */
    /* KEY: SAL sends the codec configuration (slog: "config bytes = 39") as a DATA
     * message with a subtype OTHER than 3 -- there is no format code in the header at all
     * (confirmed by disassembling pushmode_read_pkthdr). This is the initialisation that
     * was missing. */
    if (sub != 3) return 1;
    return tr_first_on_coid(coid);            /* otherwise only the start of a connection */
}

static void tr_rec(const char *what, int coid, const struct _tr_iov *iov, int parts,
                   const void *flat, size_t flatlen)
{
    pthread_mutex_lock(&tr_lock);
    if (tr_cnt >= TR_MAX) {
        tr_flush();                       /* mame dost -> zapis a dal uz nic */
        pthread_mutex_unlock(&tr_lock);
        return;
    }
    tr_cnt++;
    tr_app("%ld %s coid=0x%x parts=%d", (long)time(NULL), what, (unsigned)coid, parts);
    if (iov) {
        int i; size_t tot = 0;
        for (i = 0; i < parts; i++) tot += iov[i].len;
        tr_app(" total=%u", (unsigned)tot);
        for (i = 0; i < parts && i < 4; i++) {
            if (!iov[i].base || !iov[i].len) continue;
            tr_app(" p%d[%u]=", i, (unsigned)iov[i].len);
            tr_hexapp((const unsigned char *)iov[i].base, iov[i].len);
        }
    } else if (flat) {
        tr_app(" total=%u d=", (unsigned)flatlen);
        tr_hexapp((const unsigned char *)flat, flatlen);
    }
    tr_app("\n");
    if (tr_used + 512 > TR_BUF) tr_flush();
    pthread_mutex_unlock(&tr_lock);
}

#define TR_V(name)                                                              \
int name(int coid, const struct _tr_iov *siov, int sparts,                      \
         const struct _tr_iov *riov, int rparts)                                \
{                                                                               \
    static int (*real)(int, const struct _tr_iov *, int,                        \
                       const struct _tr_iov *, int);                            \
    if (!real) real = (int (*)(int, const struct _tr_iov *, int,                \
                               const struct _tr_iov *, int))                     \
                      dlsym(RTLD_NEXT, #name);                                   \
    if (!real) return -1;                                                        \
    if (tr_enabled() && tr_is_mdev(coid) && siov && sparts > 0 &&                \
        siov[0].base && siov[0].len == 24 &&                                      \
        tr_want_iov(coid, siov, sparts))                                           \
        tr_rec(#name, coid, siov, sparts, NULL, 0);                              \
    return real(coid, siov, sparts, riov, rparts);                               \
}
#include <dlfcn.h>
TR_V(MsgSendv)

int MsgSendvs_r(int coid, const struct _tr_iov *siov, int sparts, void *rmsg, int rbytes)
{
    static int (*real)(int, const struct _tr_iov *, int, void *, int);
    if (!real) real = (int (*)(int, const struct _tr_iov *, int, void *, int))
                      dlsym(RTLD_NEXT, "MsgSendvs_r");
    if (!real) return -1;
    if (tr_enabled() && tr_is_mdev(coid) && siov && sparts > 0 &&
        siov[0].base && siov[0].len == 24 && tr_want_iov(coid, siov, sparts))
        tr_rec("MsgSendvs_r", coid, siov, sparts, NULL, 0);
    return real(coid, siov, sparts, rmsg, rbytes);
}

int MsgSend(int coid, const void *smsg, int sbytes, void *rmsg, int rbytes)
{
    static int (*real)(int, const void *, int, void *, int);
    if (!real) real = (int (*)(int, const void *, int, void *, int))
                      dlsym(RTLD_NEXT, "MsgSend");
    if (!real) return -1;
    (void)0;   /* flat messages are other channels (audio); not logged */
    return real(coid, smsg, sbytes, rmsg, rbytes);
}

int MsgSend_r(int coid, const void *smsg, int sbytes, void *rmsg, int rbytes)
{
    static int (*real)(int, const void *, int, void *, int);
    if (!real) real = (int (*)(int, const void *, int, void *, int))
                      dlsym(RTLD_NEXT, "MsgSend_r");
    if (!real) return -1;
    (void)0;   /* flat messages are other channels (audio); not logged */
    return real(coid, smsg, sbytes, rmsg, rbytes);
}
