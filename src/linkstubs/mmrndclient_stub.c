/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Link stub for the QNX mm-renderer client. Defines only the symbols the hook references,
 * so the build resolves them without needing the vendor library. The stub is never shipped
 * to the unit: at runtime the dynamic linker binds to the real libmmrndclient.so.1 there,
 * because the SONAME matches.
 */
void *mmr_connect(const char *n)                                  { (void)n; return 0; }
void  mmr_disconnect(void *c)                                     { (void)c; }
void *mmr_context_create(void *c, const char *n, unsigned f, int m){ (void)c;(void)n;(void)f;(void)m; return 0; }
int   mmr_context_destroy(void *c)                                { (void)c; return -1; }
int   mmr_context_parameters(void *c, void *d)                    { (void)c;(void)d; return -1; }
int   mmr_input_attach(void *c, const char *u, const char *t)     { (void)c;(void)u;(void)t; return -1; }
int   mmr_input_parameters(void *c, void *d)                      { (void)c;(void)d; return -1; }
int   mmr_output_attach(void *c, const char *u, const char *t)    { (void)c;(void)u;(void)t; return -1; }
int   mmr_output_detach(void *c, unsigned o)                      { (void)c;(void)o; return -1; }
int   mmr_play(void *c)                                           { (void)c; return -1; }
