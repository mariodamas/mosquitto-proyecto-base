/*
 * fuzz_bridge_remap.c
 *
 * Target CVE:      CVE-2024-3935 (Eclipse Mosquitto — bridge topic remap
 *                  memory-corruption path).
 * Target CWE:      CWE-787 (Out-of-bounds Write) reached through CWE-120
 *                  (Classic Buffer Overflow) in bridge inbound topic rewriting.
 * Attack surface:  Broker-to-broker bridge link. Triggered when the local
 *                  broker peers with another broker and applies inbound
 *                  topic remap rules (`topic ... in/out ... local_prefix
 *                  remote_prefix`). A malicious remote broker, or an attacker
 *                  able to inject into the bridge link, can feed crafted
 *                  topic strings into `bridge__remap_topic_in`.
 * Scope:           BROKER-INTERNAL. Targets the broker's bridge module, not
 *                  the libmosquitto client.
 *
 * Compile expectations:
 *   - Built by ../build_libfuzzer.sh or ../build_afl.sh.
 *   - Include paths: -I<mosquitto>/lib -I<mosquitto>/src -I<mosquitto>/include
 *   - Links src/bridge_topic.c plus its minimal dependency set
 *     (lib/memory_mosq.c, lib/util_topic.c). The `bridge__remap_topic_in`
 *     function is non-static in v2.0.18, so it is reachable from external TUs.
 *   - The fuzzer configures a minimal `struct mosquitto__bridge` with a single
 *     remap rule drawn from fuzz input, then feeds a topic also drawn from
 *     fuzz input.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "mosquitto.h"
#include "mosquitto_broker_internal.h"

/*
 * Forward declaration so this harness does not need to rely on a broker-only
 * header being in the public include path. The signature is the one defined
 * in src/bridge_topic.c at v2.0.18.
 */
extern int bridge__remap_topic_in(struct mosquitto *context, char **topic);

/*
 * Build a NUL-terminated C string from up to `max` bytes of fuzz input,
 * stripping embedded NULs so the string-processing code under test operates
 * on well-formed C strings — the remap path assumes that, and feeding it a
 * NUL-containing buffer would only exercise glibc's strlen, not the target.
 */
static char *dup_cstring(const uint8_t *src, size_t len, size_t max)
{
	if(len > max){
		len = max;
	}
	char *out = (char *)malloc(len + 1);
	if(!out){
		return NULL;
	}
	for(size_t i = 0; i < len; i++){
		out[i] = (char)(src[i] ? src[i] : '_');
	}
	out[len] = '\0';
	return out;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	/*
	 * Layout of fuzz input:
	 *   byte 0:      direction (in / out / both) — selects how the remap
	 *                rule is applied.
	 *   byte 1:      split position for local_prefix vs remote_prefix.
	 *   byte 2:      split position for rule topic vs driven topic.
	 *   bytes 3..:   concatenated strings.
	 *
	 * This gives the fuzzer direct control over each component while
	 * keeping the driver deterministic.
	 */
	if(size < 8){
		return 0;
	}

	uint8_t direction_byte = data[0] % 3U;
	size_t local_split  = (size_t)data[1] % (size - 3);
	size_t remote_split = (size_t)data[2] % (size - 3);
	const uint8_t *payload = data + 3;
	size_t payload_size = size - 3;

	if(local_split + remote_split >= payload_size){
		return 0;
	}

	char *local_prefix  = dup_cstring(payload,                               local_split,                               64);
	char *remote_prefix = dup_cstring(payload + local_split,                 remote_split,                              64);
	char *rule_topic    = dup_cstring(payload + local_split + remote_split,  payload_size - local_split - remote_split, 256);
	char *driven_topic  = dup_cstring(payload + (payload_size / 2),          payload_size - (payload_size / 2),         256);

	if(!local_prefix || !remote_prefix || !rule_topic || !driven_topic){
		goto cleanup;
	}

	struct mosquitto__bridge_topic rule;
	memset(&rule, 0, sizeof(rule));
	rule.topic        = rule_topic;
	rule.local_prefix  = local_prefix;
	rule.remote_prefix = remote_prefix;
	rule.qos           = 0;
	switch(direction_byte){
		case 0:  rule.direction = bd_in;   break;
		case 1:  rule.direction = bd_out;  break;
		default: rule.direction = bd_both; break;
	}

	struct mosquitto__bridge bridge;
	memset(&bridge, 0, sizeof(bridge));
	bridge.topics       = &rule;
	bridge.topic_count  = 1;
	bridge.remote_clientid = (char *)"fuzz-remote";
	bridge.local_clientid  = (char *)"fuzz-local";

	struct mosquitto context;
	memset(&context, 0, sizeof(context));
	context.bridge = &bridge;

	char *driven_copy = strdup(driven_topic);
	if(driven_copy){
		(void)bridge__remap_topic_in(&context, &driven_copy);
		free(driven_copy);
	}

cleanup:
	free(local_prefix);
	free(remote_prefix);
	free(rule_topic);
	free(driven_topic);
	return 0;
}
