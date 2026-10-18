/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * alt111-dump: MST2 step 1b consumer. Stands in for direct-ts-remux on the
 * GEN2 tee port and stores the Annex-B H.264 cluster stream into a file.
 *
 *   alt111-dump OUTPUT MAX_MB MAX_SECONDS [PORT]
 *
 * Reconnects while waiting for the hook; stops at MAX_MB or MAX_SECONDS.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static time_t now_s(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec;
}

static int connect_tee(int port)
{
    struct sockaddr_in sa;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short)port);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int main(int argc, char **argv)
{
    unsigned long long limit, total = 0;
    long max_s;
    int port = 19820, out, sock = -1;
    time_t t0;
    static char buf[65536];

    if (argc < 4) {
        fprintf(stderr, "usage: %s OUTPUT MAX_MB MAX_SECONDS [PORT]\n", argv[0]);
        return 2;
    }
    limit = strtoull(argv[2], NULL, 10) * 1024ULL * 1024ULL;
    max_s = strtol(argv[3], NULL, 10);
    if (argc > 4) port = atoi(argv[4]);
    if (!limit || max_s <= 0 || port <= 0) return 2;
    signal(SIGPIPE, SIG_IGN);

    out = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) {
        fprintf(stderr, "open %s: %s\n", argv[1], strerror(errno));
        return 1;
    }
    t0 = now_s();
    printf("DUMP_START out=%s limit_mb=%s max_s=%ld port=%d\n", argv[1], argv[2], max_s, port);
    fflush(stdout);

    while (total < limit && now_s() - t0 < max_s) {
        ssize_t n;
        if (sock < 0) {
            sock = connect_tee(port);
            if (sock < 0) { sleep(2); continue; }
            printf("DUMP_CONNECTED t=%lds\n", (long)(now_s() - t0));
            fflush(stdout);
        }
        n = recv(sock, buf, sizeof(buf), 0);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            printf("DUMP_DISCONNECTED t=%lds bytes=%llu\n", (long)(now_s() - t0), total);
            fflush(stdout);
            close(sock);
            sock = -1;
            continue;
        }
        if (total + (unsigned long long)n > limit) n = (ssize_t)(limit - total);
        if (write(out, buf, (size_t)n) != n) {
            fprintf(stderr, "write: %s\n", strerror(errno));
            break;
        }
        total += (unsigned long long)n;
    }
    if (sock >= 0) close(sock);
    close(out);
    printf("DUMP_END bytes=%llu t=%lds\n", total, (long)(now_s() - t0));
    return 0;
}
