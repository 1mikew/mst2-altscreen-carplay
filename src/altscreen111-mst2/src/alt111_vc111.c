/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * alt111_vc111: Type-111 stream (natively 1010x376) -> own mm-renderer context -> cockpit.
 *
 * WHY: the earlier approach only redirected SAL's own output, i.e. mirrored the 800x480
 * main screen onto the 1024x384 cockpit display. Different aspect ratio, so the result was
 * always either distorted or letterboxed, and CarPlay disappeared from the radio screen.
 * Type-111 is the dedicated instrument-cluster stream and matches the encoder crop exactly,
 * so it needs no scaling and covers the whole surface -- and SAL's session stays untouched,
 * which is what makes two independent displays possible.
 *
 * The push protocol was recovered from SAL; see docs/PROTOCOL-MDEVPUSH.md:
 *   message = [24B header][8B PTS][AVCC NAL]
 *     u16@0x00 = 0   (data)
 *     u32@0x10 = 3   (subtype 3 = data with PTS)
 *     u32@0x14 = 8 + 4 + len(NAL)
 *     u64@0x18 = PTS in microseconds
 *     then a 4-byte BIG-ENDIAN NAL length + the NAL;  ONE NAL per message.
 *
 * Safety: everything is OFF until a configuration file exists. On any error the sink
 * disables itself permanently and only logs -- it must never break CarPlay. It is called
 * from the passive capture mirror in the gen2 adapter, which is discardable by design.
 */
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <stdint.h>
#include <sys/neutrino.h>
#include <sys/dispatch.h>

#ifndef SETIOV
#define SETIOV(_i,_a,_l) ((void)((_i)->iov_base=(void*)(_a),(_i)->iov_len=(_l)))
#endif

/* minimal mm-renderer API (linked against the unit's libmmrndclient.so.1) */
typedef struct mmr_connection mmr_connection_t;
typedef struct mmr_context mmr_context_t;
typedef struct strm_dict strm_dict_t;
extern mmr_connection_t *mmr_connect(const char *);
extern void mmr_disconnect(mmr_connection_t *);
extern mmr_context_t *mmr_context_create(mmr_connection_t *, const char *, unsigned, mode_t);
extern int mmr_context_destroy(mmr_context_t *);
extern int mmr_output_attach(mmr_context_t *, const char *, const char *);
extern int mmr_input_attach(mmr_context_t *, const char *, const char *);
extern int mmr_play(mmr_context_t *);
extern strm_dict_t *strm_dict_new(void);
extern strm_dict_t *strm_dict_set(strm_dict_t *, const char *, const char *);
extern int mmr_context_parameters(mmr_context_t *, strm_dict_t *);
extern int mmr_input_parameters(mmr_context_t *, strm_dict_t *);
extern int mmr_output_parameters(mmr_context_t *, unsigned, strm_dict_t *);
extern int mmr_output_detach(mmr_context_t *, unsigned);
extern void strm_dict_destroy(strm_dict_t *);

/* Configuration is looked up in /tmp first (session-local, cleared on reboot, for
  * experiments), then in /tsd/var/cpvc (persistent). /tsd/var is a separate writable
  * partition, so nothing has to remount the system partition read-write.
  * Kill switch: the mere existence of an "off" file -- session-local or persistent. */
#define V_DIR       "/tsd/var/cpvc/"
#define V_URLF      "/tmp/cpvc_111.url"
#define V_URLF_P    V_DIR "cpvc_111.url"
#define V_PROLOG    "/tmp/cpvc_111.prologue"   /* one hex message per line, replayed before the data */
#define V_PROLOG_P  V_DIR "cpvc_111.prologue"
#define V_OFF       "/tmp/cpvc_off"
#define V_OFF_P     V_DIR "off"
/* Optional splash: one self-contained Annex-B keyframe (SPS+PPS+IDR), built by
 * tools/make-splash.py. Without the file nothing below changes behaviour at all. */
#define V_SPLASH    "/tmp/cpvc_splash.h264"
#define V_SPLASH_P  V_DIR "splash.h264"
/* What to do with the cockpit once the phone stops sending:
 *   keep     leave the last frame up (what it always did)
 *   splash   replace it with ours
 *   release  drop our context and let the built-in map have the cockpit back
 * "release" is the one worth testing: an earlier attempt reported that destroying the
 * window wedges DisplayManager, but that was never tried from a clean disconnect. */
#define V_IDLEACT   "/tmp/cpvc_on-disconnect"
#define V_IDLEACT_P V_DIR "on-disconnect"

/* returns the first path that exists, or NULL */
static const char *v_pick(const char *a, const char *b)
{
    if (access(a, 0) == 0) return a;
    if (access(b, 0) == 0) return b;
    return NULL;
}

/* 1 = disabled by the kill switch (session-local or persistent) */
static int v_off(void)
{
    return access(V_OFF, 0) == 0 || access(V_OFF_P, 0) == 0;
}
#define V_LOG   "/tmp/cpvc_111.log"
#define V_DEV   "mdev111"
#define V_IN    "mdevpush:/dev/name/local/" V_DEV \
                "?fourcc=AVC1&video.frame_rate=30&video.depth=16" \
                "&video.width=1010&video.height=376&video.duration=0"
#define V_SEND_TO (300ULL*1000*1000)   /* 300 ms ceiling on MsgSendv */

static int v_state = 0;      /* 0 = not set up, 1 = running, -1 = permanently disabled */
static int v_coid = -1;
static unsigned v_tick = 0;
static long v_sent = 0, v_fail = 0;
static int  v_retries = 0;
/* Header fields SAL happens to set (observed: w1=0x1c, w2=1, w3=0x144a). The consumer
  * never reads them -- they are stack garbage in SAL's own messages -- but they stay
  * tunable from the configuration so a firmware that does read them needs no rebuild. */
static unsigned v_w1 = 0x1c, v_w2 = 1, v_w3 = 0x144a;
/* Input URL including the declared resolution, third configuration line. The i.MX6 VPU
  * wants dimensions aligned to 16, which is why 1024x384 (the encoded size) is declared
  * rather than the 1010x376 visible size. Tunable at runtime, no rebuild needed. */
static char v_inurl[512];
/* The output URL currently in use. When the file changes we tear the context down and
  * rebuild it -- otherwise a change would only take effect after a reboot of the unit,
  * which makes tuning the geometry needlessly expensive. */
static char v_used[768];
static time_t v_last_feed;      /* when the last frame arrived -- used to clean up after the phone disconnects */
static int v_oid = -1;          /* id of our video output */
static int v_hidden;            /* 1 = we moved out of the way */
static int v_hide_broken;       /* 1 = runtime geometry change does not work here; stop trying */
/* SPS and PPS are collected CONTINUOUSLY: they are not necessarily in the same access
  * unit as the keyframe (confirmed on the vehicle) and often arrive earlier on their own.
  * Without them no avcC can be built and the decoder ends in error::5. */
static uint8_t v_sps[128], v_pps[64];
static size_t  v_sps_n, v_pps_n;
static mmr_connection_t *v_conn;
static mmr_context_t *v_ctx;

static void v_log(const char *fmt, ...)
{
    FILE *f = fopen(V_LOG, "a");
    va_list ap;
    if (!f) return;
    fprintf(f, "%ld ", (long)time(NULL));
    va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}

static uint64_t v_now_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ull + (uint64_t)(ts.tv_nsec / 1000);
}

/* read the output URL; NULL = disabled */
static const char *v_cfg(char *buf, size_t n)
{
    char l2[128];
    const char *path;
    FILE *f;
    if (v_off()) return NULL;
    path = v_pick(V_URLF, V_URLF_P);
    if (!path) return NULL;
    f = fopen(path, "r");
    if (!f) return NULL;
    if (!fgets(buf, (int)n, f)) { fclose(f); return NULL; }
    if (fgets(l2, sizeof(l2), f)) {           /* optional: "w1 w2 w3" in hex */
        unsigned a, b, c;
        if (sscanf(l2, "%x %x %x", &a, &b, &c) == 3) { v_w1 = a; v_w2 = b; v_w3 = c; }
    }
    { char l4[64]; long pos = ftell(f); (void)pos; }
    if (fgets(v_inurl, sizeof(v_inurl), f)) {  /* optional: the full input URL */
        char *e = v_inurl + strlen(v_inurl);
        while (e > v_inurl && (e[-1]=='\n'||e[-1]=='\r'||e[-1]==' ')) *--e = 0;
        if (v_inurl[0] != 'm') v_inurl[0] = 0;     /* must start with "mdevpush:" */
    }
    fclose(f);
    { char *e = buf + strlen(buf);
      while (e > buf && (e[-1]=='\n'||e[-1]=='\r'||e[-1]==' ')) *--e = 0; }
    return (buf[0] && buf[0] != '#') ? buf : NULL;
}

/* one message: [24B header][8B PTS][4B BE length + NAL] */
static int v_push_nal(const uint8_t *nal, uint32_t len, uint64_t pts)
{
    uint8_t hdr[24], be[4];
    iov_t iov[4];
    uint64_t to = V_SEND_TO;
    int rc;

    memset(hdr, 0, sizeof(hdr));
    /* Fields 0x04/0x08/0x0c are stack garbage in SAL's own messages and the consumer
     * never reads them (confirmed in pushmode_read_pkthdr). Kept configurable only so a
     * future firmware that does read them can be matched without a rebuild. */
    *(uint32_t *)(hdr + 0x04) = v_w1;
    *(uint32_t *)(hdr + 0x08) = v_w2;
    *(uint32_t *)(hdr + 0x0c) = v_w3;
    *(uint16_t *)(hdr + 0x00) = 0;                 /* data               */
    *(uint32_t *)(hdr + 0x10) = 3;                 /* subtype 3 = +PTS  */
    *(uint32_t *)(hdr + 0x14) = 8u + 4u + len;     /* length after header*/
    be[0]=(uint8_t)(len>>24); be[1]=(uint8_t)(len>>16);
    be[2]=(uint8_t)(len>>8);  be[3]=(uint8_t)len;  /* 4B BIG-ENDIAN     */

    SETIOV(&iov[0], hdr, 24);
    SETIOV(&iov[1], &pts, 8);
    SETIOV(&iov[2], be, 4);
    SETIOV(&iov[3], (void *)nal, len);

    TimerTimeout(CLOCK_MONOTONIC, _NTO_TIMEOUT_SEND|_NTO_TIMEOUT_REPLY, NULL, &to, NULL);
    rc = MsgSendv(v_coid, iov, 4, NULL, 0);
    return (rc == -1) ? -1 : 0;
}

/* extract SPS/PPS from an avcC and push them as NALs (decoder priming) */
static void v_prime_from_avcc(const uint8_t *c, size_t n)
{
    size_t p;
    unsigned i, cnt;
    if (!c || n < 7) return;
    p = 5;
    cnt = c[p++] & 0x1f;                      /* numSPS */
    for (i = 0; i < cnt && p + 2 <= n; i++) {
        unsigned l = (unsigned)((c[p] << 8) | c[p+1]); p += 2;
        if (p + l > n) return;
        v_push_nal(c + p, l, v_now_us()); p += l;
    }
    if (p >= n) return;
    cnt = c[p++];                             /* numPPS */
    for (i = 0; i < cnt && p + 2 <= n; i++) {
        unsigned l = (unsigned)((c[p] << 8) | c[p+1]); p += 2;
        if (p + l > n) return;
        v_push_nal(c + p, l, v_now_us()); p += l;
    }
    v_log("priming z avcC hotovo (%u B)", (unsigned)n);
}

static void v_teardown(void)
{
    if (v_coid >= 0) { name_close(v_coid); v_coid = -1; }
    if (v_ctx) { mmr_context_destroy(v_ctx); v_ctx = NULL; }
    if (v_conn) { mmr_disconnect(v_conn); v_conn = NULL; }
    v_state = 0;
}

static int v_setup(const char *out_url, const uint8_t *cfg, size_t cfg_n)
{
    int oid, tries;
    v_conn = mmr_connect(NULL);
    if (!v_conn) { v_log("ERROR mmr_connect"); return -1; }
    v_ctx = mmr_context_create(v_conn, "cpvc111", 0, 0777);
    if (!v_ctx) { v_log("ERROR context_create"); return -1; }
    { strm_dict_t *d = strm_dict_new();
      if (d) { d = strm_dict_set(d, "prefetch_mode", "-1"); mmr_context_parameters(v_ctx, d); } }
    oid = mmr_output_attach(v_ctx, out_url, "video");
    if (oid < 0) { v_log("ERROR output_attach url=%s", out_url); return -1; }
    v_oid = oid; v_hidden = 0;
    { const char *in = v_inurl[0] ? v_inurl : V_IN;
      if (mmr_input_attach(v_ctx, in, "track") < 0) { v_log("ERROR input_attach in=%s", in); return -1; }
      v_log("input: %s", in); }
    { strm_dict_t *d = strm_dict_new();
      if (d) { d = strm_dict_set(d, "VideoDecoderLowLatencyMode", "1");
               mmr_input_parameters(v_ctx, d); } }
    if (mmr_play(v_ctx) < 0) { v_log("ERROR mmr_play"); return -1; }
    for (tries = 0; tries < 30 && v_coid < 0; tries++) {
        v_coid = name_open(V_DEV, 0);
        if (v_coid < 0) usleep(100000);
    }
    if (v_coid < 0) { v_log("ERROR name_open('%s')", V_DEV); return -1; }

    /* Fallback: replay a start-up sequence from a file (one hex message per line).
     * Lets any observed initialisation be reproduced without a rebuild. */
    /* DECODER INITIALISATION, built from the LIVE stream.
     * A prologue file carries an avcC frozen from some past capture; if the phone then
     * negotiates different stream parameters the decoder is configured for something else
     * and the result is a black picture with no error at all. So prefer the live one.
     * Message layout recovered from SAL, see docs/PROTOCOL-MDEVPUSH.md:
     *   subtype 5 (4 B)   = start / flush
     *   subtype 2 (32 B)  = descriptor: fourcc AVC1, width, height, depth, frame rate
     *   subtype 4 (N+4)   = avcC + 02000000 */
    if (cfg && cfg_n) {
        unsigned char m[512];
        unsigned w = 1024, h = 384;
        const char *q;
        int rc, n;
        if ((q = strstr(v_inurl[0] ? v_inurl : V_IN, "video.width=")) != NULL)  w = (unsigned)atoi(q + 12);
        if ((q = strstr(v_inurl[0] ? v_inurl : V_IN, "video.height=")) != NULL) h = (unsigned)atoi(q + 13);

        memset(m, 0, 24);
        *(uint32_t *)(m + 0x10) = 5; *(uint32_t *)(m + 0x14) = 4;
        *(uint32_t *)(m + 24) = 1;
        rc = MsgSend(v_coid, m, 28, NULL, 0);
        v_log("init subtype 5 rc=%d", rc);

        memset(m, 0, 24);
        *(uint32_t *)(m + 0x10) = 2; *(uint32_t *)(m + 0x14) = 32;
        *(uint32_t *)(m + 24 +  0) = 2;
        m[24 + 4] = 0x31; m[24 + 5] = 0x43; m[24 + 6] = 0x56; m[24 + 7] = 0x41;  /* 'AVC1' LE */
        *(uint32_t *)(m + 24 +  8) = w;
        *(uint32_t *)(m + 24 + 12) = h;
        *(uint32_t *)(m + 24 + 16) = 16;
        *(uint32_t *)(m + 24 + 20) = 30;
        rc = MsgSend(v_coid, m, 24 + 32, NULL, 0);
        v_log("init subtype 2 rc=%d (%ux%u)", rc, w, h);

        if (cfg_n + 4u + 24u <= sizeof(m)) {
            memset(m, 0, 24);
            *(uint32_t *)(m + 0x10) = 4; *(uint32_t *)(m + 0x14) = (uint32_t)cfg_n + 4u;
            memcpy(m + 24, cfg, cfg_n);
            *(uint32_t *)(m + 24 + cfg_n) = 2;
            n = (int)(24 + cfg_n + 4);
            rc = MsgSend(v_coid, m, n, NULL, 0);
            v_log("init subtype 4 rc=%d (live avcC %u B, profile 0x%02x level %u)",
                  rc, (unsigned)cfg_n, cfg[1], cfg[3]);
        } else {
            v_log("live avcC too large (%u B); falling back to the file", (unsigned)cfg_n);
        }
    }
    else { const char *pp = v_pick(V_PROLOG, V_PROLOG_P);
      FILE *pf = pp ? fopen(pp, "r") : NULL;
      if (pp) v_log("prologue from %s", pp);
      if (pf) {
          char line[4096]; int nmsg = 0;
          while (fgets(line, sizeof(line), pf)) {
              size_t n = 0, i, L = strlen(line);
              static unsigned char msg[2048];
              if (line[0] == '#') continue;
              for (i = 0; i + 1 < L && n < sizeof(msg); i += 2) {
                  int hi = line[i], lo = line[i+1], a, b;
                  if (hi == '\n' || hi == '\r' || hi == ' ') break;
                  a = (hi >= 'a') ? hi - 'a' + 10 : (hi >= 'A' ? hi - 'A' + 10 : hi - '0');
                  b = (lo >= 'a') ? lo - 'a' + 10 : (lo >= 'A' ? lo - 'A' + 10 : lo - '0');
                  if (a < 0 || a > 15 || b < 0 || b > 15) break;
                  msg[n++] = (unsigned char)((a << 4) | b);
              }
              if (n >= 2) {
                  uint64_t to = V_SEND_TO; int rc;
                  TimerTimeout(CLOCK_MONOTONIC, _NTO_TIMEOUT_SEND|_NTO_TIMEOUT_REPLY, NULL, &to, NULL);
                  rc = MsgSend(v_coid, msg, (int)n, NULL, 0);
                  v_log("  prologue #%d (%u B) -> rc=%d", ++nmsg, (unsigned)n, rc);
              }
          }
          fclose(pf);
      } }
    v_log("RUNNING: out=%s coid=%d hdr w1=%x w2=%x w3=%x", out_url, v_coid, v_w1, v_w2, v_w3);
    return 0;
}

/* Build an avcC from the SPS/PPS seen in the incoming Annex-B stream.
  * Why not from the configuration the hook hands us: that has a different layout (its
  * first byte is not 0x01, and reading it as an avcC gives profile 0x00 / level 1), the
  * decoder got nonsense from it and returned error::5 -- a black cockpit.
  *   avcC = 01 profile compat level FF E1 <2B SPS len> SPS 01 <2B PPS len> PPS */
/* walk an Annex-B access unit and remember SPS/PPS if present */
static void v_scan_params(const uint8_t *au, size_t n)
{
    size_t p = 0;
    while (p + 3 <= n && !(au[p] == 0 && au[p+1] == 0 && au[p+2] == 1)) p++;
    while (p + 3 <= n) {
        size_t st = p + 3, j = st, end, l;
        while (j + 3 <= n && !(au[j] == 0 && au[j+1] == 0 && au[j+2] == 1)) j++;
        end = (j + 3 <= n) ? j : n;
        l = end - st;
        while (l > 0 && au[st + l - 1] == 0) l--;
        if (l > 1) {
            unsigned t = au[st] & 0x1f;
            if (t == 7 && l <= sizeof(v_sps)) { memcpy(v_sps, au + st, l); v_sps_n = l; }
            else if (t == 8 && l <= sizeof(v_pps)) { memcpy(v_pps, au + st, l); v_pps_n = l; }
        }
        p = end;
    }
}

static size_t v_build_avcc(uint8_t *out, size_t outmax)
{
    const uint8_t *sps = v_sps, *pps = v_pps;
    size_t sps_n = v_sps_n, pps_n = v_pps_n, need;

    if (!sps_n || !pps_n || sps_n < 4) return 0;

    need = 6 + 2 + sps_n + 1 + 2 + pps_n;
    if (need > outmax) return 0;
    out[0] = 1; out[1] = sps[1]; out[2] = sps[2]; out[3] = sps[3];
    out[4] = 0xff;                     /* 6b reserved + 4-byte NAL length */
    out[5] = 0xe1;                     /* 3b reserved + 1 SPS               */
    out[6] = (uint8_t)(sps_n >> 8); out[7] = (uint8_t)sps_n;
    memcpy(out + 8, sps, sps_n);
    out[8 + sps_n] = 1;                /* 1 PPS */
    out[9 + sps_n] = (uint8_t)(pps_n >> 8); out[10 + sps_n] = (uint8_t)pps_n;
    memcpy(out + 11 + sps_n, pps, pps_n);
    return need;
}

/* ---- splash ------------------------------------------------------------- */
/* The decoder shows nothing until it is handed a keyframe, and Type-111 sends one only
 * about every 29 s. So we keep one of our own: it fills the gap after a connect, and it
 * is the only thing that clears the frame left frozen on the cockpit when the phone goes
 * away -- shrinking or destroying the window was tried and does not work here.
 * The splash runs in its own context, primed from its own SPS/PPS; the real stream has
 * different ones, so the first genuine IDR tears this down and starts over. */
static int v_splash_on;                       /* the running context is showing the splash */

static int v_splash_show(const char *out_url)
{
    static uint8_t buf[65536];
    const uint8_t *sps = NULL, *pps = NULL, *idr = NULL;
    size_t sps_n = 0, pps_n = 0, idr_n = 0, got;
    uint8_t cfg[256];
    size_t cfg_n, p;
    const char *path = v_pick(V_SPLASH, V_SPLASH_P);
    FILE *f;

    if (!path) return -1;
    f = fopen(path, "rb");
    if (!f) return -1;
    got = fread(buf, 1, sizeof(buf), f);
    fclose(f);
    if (got < 8) return -1;

    /* Walk the Annex-B units and keep the three that matter. */
    p = 0;
    while (p + 3 <= got) {
        size_t st, end;
        if (!(buf[p] == 0 && buf[p+1] == 0 && buf[p+2] == 1)) { p++; continue; }
        st = p + 3;
        end = st;
        while (end + 3 <= got && !(buf[end] == 0 && buf[end+1] == 0 && buf[end+2] == 1)) end++;
        if (end + 3 > got) end = got;
        while (end > st && buf[end-1] == 0) end--;      /* trailing zero padding */
        if (end > st) {
            unsigned t = buf[st] & 0x1fu;
            if (t == 7)      { sps = buf + st; sps_n = end - st; }
            else if (t == 8) { pps = buf + st; pps_n = end - st; }
            else if (t == 5) { idr = buf + st; idr_n = end - st; }
        }
        p = end;
    }
    if (!sps || !pps || !idr || sps_n < 4) {
        v_log("splash %s is unusable (SPS=%u PPS=%u IDR=%u)",
              path, (unsigned)sps_n, (unsigned)pps_n, (unsigned)idr_n);
        return -1;
    }

    cfg_n = 6 + 2 + sps_n + 1 + 2 + pps_n;
    if (cfg_n > sizeof(cfg)) return -1;
    cfg[0] = 1; cfg[1] = sps[1]; cfg[2] = sps[2]; cfg[3] = sps[3];
    cfg[4] = 0xff; cfg[5] = 0xe1;
    cfg[6] = (uint8_t)(sps_n >> 8); cfg[7] = (uint8_t)sps_n;
    memcpy(cfg + 8, sps, sps_n);
    cfg[8 + sps_n] = 1;
    cfg[9 + sps_n] = (uint8_t)(pps_n >> 8); cfg[10 + sps_n] = (uint8_t)pps_n;
    memcpy(cfg + 11 + sps_n, pps, pps_n);

    v_teardown();
    if (v_setup(out_url, cfg, cfg_n) < 0) { v_teardown(); return -1; }
    if (v_push_nal(idr, (uint32_t)idr_n, v_now_us()) < 0) { v_teardown(); return -1; }
    v_splash_on = 1;
    v_log("splash shown from %s (%u B keyframe)", path, (unsigned)idr_n);
    return 0;
}

/* ---- watchdog: cockpit composition has stalled --------------------------- */
/* DisplayManager only captures dpy-6 when Screen reports a change; otherwise its loop
  * sits in screen_get_event and times out every 2 s. Our window rides a hardware video
  * plane and generates no such event, so once the content underneath stops redrawing the
  * cluster freezes on the last frame -- observed after a reboot of the unit.
  * So watch the composition counter: if it stands still while we are still pushing frames,
  * tear the context down (recreating the window does generate an event) and ask for a
  * keyframe so it comes back quickly instead of waiting for the regular one (~29 s). */
#define V_DPY6     "/dev/screen/0/dpy-6"
#define V_KEYFRAME "/tmp/mibr-alt111-keyframe-only"

/* read the composition counter from the dpy-6 dump, and whether capture is active */
static unsigned long v_dpy_counter(int *snima)
{
    FILE *f = fopen(V_DPY6, "r");
    char line[160];
    unsigned long v = 0;
    if (snima) *snima = -1;
    if (!f) return 0;
    while (fgets(line, sizeof(line), f)) {
        if (!v && strncmp(line, "counter", 7) == 0) {
            char *e = strchr(line, '=');
            if (e) v = strtoul(e + 1, NULL, 10);
        } else if (snima && strncmp(line, "capture buffer", 14) == 0) {
            *snima = (strstr(line, "(none)") == NULL);
        }
    }
    fclose(f);
    return v;
}

static void v_watchdog(void)
{
    static unsigned long last_counter, last_sent;
    static int stalls;
    static time_t last_nudge;
    static int no_capture;
    int snima = -1;
    unsigned long c = v_dpy_counter(&snima);

    if (!c) return;                                   /* unreadable -> ignore */

    /* A different failure than stalled composition: composition runs, but DisplayManager
     * is not capturing at all (capture buffer = none). That happens when the cluster has
     * no FPK video connection -- the log shows "fpkUpdateTargetState(streaming): 2 -> 2"
     * instead of "0 -> 1" plus "Start transmission". Only the HMI/cluster can rebuild it
     * (by switching the cockpit view); we have no handle on it. So just report it, and
     * above all do not tear anything down over it, because that would not help. */
    if (snima == 0) {
        if (++no_capture >= 3) {
            no_capture = 0;
            v_log("DisplayManager stopped capturing (counter=%lu) -> moving out of the cockpit so the "
                  "stock map redraws and the cluster can rebuild its video connection", c);
            v_teardown(); v_retries = 0;        /* we come back once capture resumes */
        }
        return;
    }
    if (snima == 1 && no_capture) {
        v_log("DisplayManager zase snima, pokracujeme");
        no_capture = 0;
    }
    if (last_counter && c == last_counter && (unsigned long)v_sent != last_sent) {
        if (++stalls >= 2) {                          /* two consecutive checks */
            time_t now = time(NULL);
            stalls = 0;
            if (now - last_nudge < 30) return;        /* do not keep tearing it down */
            last_nudge = now;
            v_log("dpy-6 composition stalled (counter=%lu) while we are still pushing -> tearing the context down and requesting a keyframe", c);
            { FILE *k = fopen(V_KEYFRAME, "w"); if (k) fclose(k); }
            v_teardown(); v_retries = 0;
            last_counter = 0; last_sent = 0;
            return;
        }
    } else {
        stalls = 0;
    }
    last_counter = c;
    last_sent = (unsigned long)v_sent;
}

/* Called from the gen2 output thread even when no frames are arriving.
  *
  * Without this, our window stays on dpy-6 after the iPhone disconnects, keeps covering
  * the built-in map, and the cluster is left with the last CarPlay frame. The wanted
  * behaviour is the opposite: without a phone the built-in map runs, with a phone CarPlay
  * takes over. So get out of the way when nothing arrives for a while; when the phone
  * comes back the context is rebuilt on the first keyframe. */
#define V_IDLE_S 5

/* Move out of the way by changing zorder. Why not simply tear the context down:
  * destroying the window sends DisplayManager a SCREEN_EVENT_CLOSE for a window it does
  * not manage ("Unknown/Unmanaged window was closed") and its capture state machine wedges
  * afterwards -- composition keeps running but the capture buffer stays (none), so not
  * even the stock map reaches the cluster. Changing zorder is a far smaller intervention:
  * the window stays, it just hides below the map (which sits at order 3). */
/* NOTE: mmr_output_parameters("VideoWriterZOrder") returns rc=0 and DOES NOTHING
  * (verified on the vehicle -- the same trap as VideoWriterSrcX earlier). Geometry has to
  * be changed by detaching and re-attaching the output instead; the window is destroyed
  * for an instant but a new one appears immediately. */
static int v_reattach(const char *url)
{
    int oid;
    if (!v_ctx || v_oid < 0) return -1;
    if (mmr_output_detach(v_ctx, (unsigned)v_oid) < 0) { v_log("output_detach failed"); return -1; }
    oid = mmr_output_attach(v_ctx, url, "video");
    if (oid < 0) { v_log("output_attach(%s) failed", url); v_oid = -1; return -1; }
    v_oid = oid;
    return 0;
}

void vc111_idle_tick(void)
{
    if (v_state != 1 || !v_last_feed) return;
    if (time(NULL) - v_last_feed < V_IDLE_S) return;
    /* The phone is gone and the cockpit is holding its last frame. Replacing it with the
     * splash is what finally works: shrinking the window fails (mmr_output_detach is
     * refused on a playing context) and destroying it wedges DisplayManager. */
    {
        char act[32] = "keep";
        const char *ap = v_pick(V_IDLEACT, V_IDLEACT_P);
        if (ap) {
            FILE *af = fopen(ap, "r");
            if (af) {
                if (fgets(act, sizeof(act), af)) {
                    char *e = act + strlen(act);
                    while (e > act && (e[-1]=='\n'||e[-1]=='\r'||e[-1]==' '||e[-1]=='\t')) *--e = 0;
                }
                fclose(af);
            }
        }
        if (strcmp(act, "release") == 0) {
            /* Give the cockpit back. Whether the built-in map actually redraws is the
             * open question -- it stops while our window covers it, and DisplayManager
             * only captures when Screen reports a change. */
            v_log("no frames for %d s -> releasing the cockpit (on-disconnect=release)", V_IDLE_S);
            v_teardown(); v_splash_on = 0;
            return;
        }
        if (strcmp(act, "splash") == 0 && !v_splash_on) {
            char url[768];
            const char *out = v_cfg(url, sizeof(url));
            if (out && v_splash_show(out) == 0) {
                v_log("no frames for %d s -> splash (on-disconnect=splash)", V_IDLE_S);
                return;
            }
        }
    }
    if (1) return;
    if (v_hidden || v_hide_broken) return;
    v_hidden = 1;
    v_log("no frames for %d s (phone disconnected?) -> shrinking the window to 1 px so the "
          "built-in map comes back", V_IDLE_S);
    { int rc = v_reattach("screen:/?index=1&overlay=0&dstx=0&dsty=0&dstw=1&dsth=1&zorder=500");
      v_log("  shrink rc=%d", rc);
      if (rc < 0) { v_hide_broken = 1; v_hidden = 0;
                    v_log("  runtime geometry change does not work here; not trying again"); } }
}

/* Is our cockpit sink running? Used by the gen2 output thread so the stream does not
  * need an external consumer on 127.0.0.1:19820 -- without one the data used to be
  * dropped before it ever got here. Cheap: the file is only stat'ed occasionally and the
  * result cached in between. */
int vc111_wants_data(void)
{
    static unsigned tick;
    static int cached;
    if (v_state < 0) return 0;                 /* permanently disabled after errors */
    if ((tick++ & 0x7f) == 0)
        cached = (!v_off() && v_pick(V_URLF, V_URLF_P) != NULL);
    return cached;
}

void vc111_feed(const uint8_t *au, size_t n, unsigned nal_len_size,
                const uint8_t *avcc_cfg, size_t cfg_len, unsigned idr)
{
    char url[768];
    const char *out;
    size_t p = 0;
    uint64_t pts;
    (void)idr;

    if (v_state < 0) return;                       /* natrvalo vypnuto */
    if (!au || !n) return;
    if (v_splash_on && idr) {
        /* The stream has its own parameter sets; keep nothing of ours. */
        v_log("stream keyframe -> dropping the splash");
        v_teardown(); v_splash_on = 0;
    }
    v_last_feed = time(NULL);
    v_scan_params(au, n);
    if (v_hidden && v_state == 1) {               /* frames are back -> cover the cockpit again */
        char back[768];
        v_hidden = 0;
        if (v_cfg(back, sizeof(back)))
            v_log("frames are back -> covering the cockpit again, rc=%d", v_reattach(back));
    }
    (void)nal_len_size;   /* nepouziva se: vstup je Annex-B */

    if (v_state == 1 && (v_tick++ & 0xff) == 0) {
        char chk[768];
        const char *c = v_cfg(chk, sizeof(chk));
        if (!c) {                                  /* konfigurace zmizela = vypnout */
            v_log("configuration removed -> tearing the context down");
            v_teardown(); return;
        }
        if (strcmp(c, v_used) != 0) {
            v_log("configuration CHANGED -> tearing down, rebuilding on the next IDR");
            v_log("  old: %s", v_used);
            v_log("  new: %s", c);
            v_teardown(); v_retries = 0; return;
        }
        v_watchdog();
    }

    if (v_state == 0) {
        /* We MUST start on a keyframe: starting mid-GOP means the engine never sees the
         * parameter sets and fails with error 5 (verified). */
        if (!idr) {
            /* Start je navazany na klicovy snimek a ten chodi jen ~1x za 29 s - cekani
             * je citelne. Rekneme si o nej sami: gen2 marker ho spotrebuje a vyvola
             * forceKeyFrame. Zkouska nejvyse jednou za 10 s, at nezahltime telefon. */
            static time_t last_req;
            time_t now = time(NULL);
            if (now - last_req >= 10) {
                FILE *k;
                last_req = now;
                k = fopen(V_KEYFRAME, "w");
                if (k) { fclose(k); v_log("waiting for a keyframe; requesting one"); }
            }
            /* Cover the wait with our own picture rather than whatever the cockpit is
             * still holding. Only once DisplayManager is capturing -- same reason as the
             * real start below. */
            if (!v_splash_on) {
                int snima = -1;
                (void)v_dpy_counter(&snima);
                if (snima == 1) {
                    char url[768];
                    const char *out = v_cfg(url, sizeof(url));
                    if (out) (void)v_splash_show(out);
                }
            }
            v_tick++; return;
        }
        out = v_cfg(url, sizeof(url));
        if (!out) return;                          /* vypnuto souborem */
        /* DO NOT take over the cockpit too early. Our window covers the map, the map
         * stops redrawing, and while the cluster has no FPK video connection there is
         * nothing left to rebuild it from -- the cluster then keeps a frozen frame from
         * the previous session (observed after a reboot). So wait until DisplayManager is
         * actually capturing. */
        { int snima = -1;
          (void)v_dpy_counter(&snima);
          if (snima == 0) {
              static int hlaseno;
              if (!hlaseno) { hlaseno = 1; v_log("waiting for DisplayManager to start capturing the cockpit (capture buffer = none)"); }
              return;
          } }
        { uint8_t built[256];
          size_t bn = v_build_avcc(built, sizeof(built));
          /* Once SPS+PPS have been seen in the stream, build the avcC ourselves (more
           * accurate). Otherwise send the hook's configuration AS IS -- it is verified to
           * work even though it does not start with 0x01. An earlier "sanity check"
           * rejected it and broke a working setup. */
          if (bn) {
              avcc_cfg = built; cfg_len = bn;
              v_log("avcC built from the stream: %u B, profile 0x%02x, level %u",
                    (unsigned)bn, built[1], built[3]);
          } else {
              v_log("no SPS/PPS yet; sending the hook configuration as is (%u B)", (unsigned)cfg_len);
          }
        if (v_setup(out, avcc_cfg, cfg_len) < 0) { v_teardown(); 
            if (++v_retries > 3) { v_state = -1; v_log("SINK DISABLED (setup failed %d times)", v_retries); }
            return; } }
        v_state = 1; v_fail = 0;
        strncpy(v_used, out, sizeof(v_used) - 1); v_used[sizeof(v_used) - 1] = 0;
    }

    pts = v_now_us();
    /* NOTE: the input is ANNEX-B, not AVCC. alt111_video_submit() converts on enqueue
     * (inserting 4-byte start codes) and prepends the parameter sets, so there are no NAL
     * lengths here. The conversion to AVCC (4-byte BE length) happens on push below. */
    while (p + 3 <= n && !(au[p] == 0 && au[p+1] == 0 && au[p+2] == 1)) p++;
    while (p + 3 <= n) {
        size_t s = p + 3, j = s, end; size_t l;
        while (j + 3 <= n && !(au[j] == 0 && au[j+1] == 0 && au[j+2] == 1)) j++;
        end = (j + 3 <= n) ? j : n;
        l = end - s;
        while (l > 0 && au[s + l - 1] == 0) l--;    /* zero_byte pred dalsim start kodem */
        if (l > 0) {
            if (v_push_nal(au + s, (uint32_t)l, pts) < 0) {
                if (++v_fail > 30) {
                    v_log("errors=%ld (ok=%ld) -> tearing down, retrying on the next IDR",
                          v_fail, v_sent);
                    v_teardown();
                    if (++v_retries > 3) { v_state = -1; v_log("SINK DISABLED (%d failures)", v_retries); }
                    return;
                }
            } else {
                v_sent++;
                if ((v_sent % 300) == 1) v_log("NALs sent=%ld errors=%ld", v_sent, v_fail);
            }
        }
        p = end;
    }
}
