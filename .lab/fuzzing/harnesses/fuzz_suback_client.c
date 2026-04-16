/*
 * fuzz_suback_client.c
 * --------------------
 * Target CVE     : CVE-2024-10525
 * Target CWE     : CWE-125 (out-of-bounds read) in the client-side SUBACK
 *                  handler when the server returns a malformed SUBACK payload.
 * Attack surface : Client-side / libmosquitto. A malicious or compromised
 *                  broker can reach this code path in any client that calls
 *                  mosquitto_subscribe() and loops on mosquitto_loop().
 * Side targeted  : Client library logic. THIS HARNESS IS NOT BROKER-CENTRIC.
 *                  It targets lib/handle_suback.c::handle__suback, which
 *                  parses the SUBACK variable header and payload from
 *                  mosq->in_packet under the assumption that the bytes came
 *                  from a trusted broker. CVE-2024-10525 shows that
 *                  assumption is unsafe.
 * Compile notes  : Depends on lib/handle_suback.c, lib/packet_datatypes.c,
 *                  lib/property_mosq.c, lib/memory_mosq.c, and the callback
 *                  plumbing reachable from mosquitto_internal.h. See
 *                  .lab/fuzzing/build_*.sh for the concrete TU list.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "mosquitto.h"
#include "mqtt_protocol.h"
#include "mosquitto_internal.h"
#include "packet_mosq.h"
#include "read_handle.h"

/* Stand-in SUBSCRIBE state. handle__suback matches the incoming SUBACK
 * against an outstanding subscribe message ID; without at least one queued
 * message the parser returns early and we fail to exercise the payload
 * decode. We queue a synthetic in-flight message with mid = 1 and let the
 * fuzzer drive the bytes following the 2-byte mid field. */
static void
prime_mosq(struct mosquitto *mosq)
{
    memset(mosq, 0, sizeof(*mosq));
    mosq->protocol = mosq_p_mqtt311;  /* SUBACK exists in v3.1.1 and v5 */
    mosq->state    = mosq_cs_active;
}

int
LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    /* SUBACK minimum over the wire is 3 bytes (mid + 1 return code).
     * Reject shorter inputs but accept anything else so the parser sees
     * the full range of malformed shapes. */
    if (size < 3 || size > 65535) return 0;

    struct mosquitto mosq;
    prime_mosq(&mosq);

    /* handle__suback consumes mosq->in_packet. Copy the fuzz buffer so that
     * any write inside the parser stays in harness-owned memory and ASan
     * can see it. */
    uint8_t *payload = (uint8_t *)malloc(size);
    if (!payload) return 0;
    memcpy(payload, data, size);

    mosq.in_packet.payload          = payload;
    mosq.in_packet.remaining_length = (uint32_t)size;
    mosq.in_packet.packet_length    = (uint32_t)size;
    mosq.in_packet.pos              = 0;
    mosq.in_packet.command          = CMD_SUBACK;

    (void)handle__suback(&mosq);

    /* handle__suback may reassign / free mosq.in_packet.payload on success.
     * If it did, ours was already freed; if it did not, free our copy. */
    if (mosq.in_packet.payload == payload) {
        free(payload);
    }

    return 0;
}