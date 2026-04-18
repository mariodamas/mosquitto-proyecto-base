#include "mosquitto.h"

/*
 * Minimal logger stub for standalone harness builds.
 * The parser path under test does not require broker logging side effects.
 */
int log__printf(struct mosquitto *mosq, unsigned int level, const char *fmt, ...)
{
    (void)mosq;
    (void)level;
    (void)fmt;
    return 0;
}
