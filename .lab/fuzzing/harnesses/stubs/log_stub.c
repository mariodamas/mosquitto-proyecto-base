#include <stdarg.h>
#include "mosquitto.h"
int log__printf(struct mosquitto *mosq, unsigned int priority, const char *fmt, ...)
{
   (void)mosq;
   (void)priority;
   (void)fmt;
   return MOSQ_ERR_SUCCESS;
}
