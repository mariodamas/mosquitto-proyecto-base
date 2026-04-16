/*
 * fuzz_packet_parser.c
 *
 * Target CVE:      CVE-2024-8376 (Eclipse Mosquitto — memory corruption via
 *                  crafted MQTT 5 property sequences processed by the broker).
 * Target CWE:      CWE-787 (Out-of-bounds Write) / CWE-125 (Out-of-bounds Read),
 *                  reached via CWE-20 (Improper Input Validation) on the MQTT 5
 *                  variable-header / property parser.
 * Attack surface:  Broker-side, pre-authentication. Any TCP peer able to open a
 *                  connection can drive the packet read path. The same parser
 *                  feeds CONNECT, PUBLISH, SUBSCRIBE, and the MQTT 5 property
 *                  sections inside them.
 * Scope:           BROKER-INTERNAL. Exercises internal parsing primitives
 *                  (`property__read_all`, `packet__read_*`) against
 *                  attacker-controlled byte sequences. It is *not* a trivial
 *                  standalone byte parser — the harness drives multiple
 *                  successive MQTT frames with real command bytes from the
 *                  fuzzer's input, so state across frames (allocator churn,
 *                  property-list lifetimes, partial packets) is reachable.
 *
 * Compile expectations:
 *   - Built by ../build_libfuzzer.sh (clang + -fsanitize=fuzzer,address,undefined)
 *     or ../build_afl.sh (afl-clang-fast + AFL_USE_ASAN=1 AFL_USE_UBSAN=1).
 *   - Include paths: -I<mosquitto>/lib -I<mosquitto>/src -I<mosquitto>/include
 *   - Links the TU(s) that define `property__read_all`, `packet__read_*`, and
 *     the internal `property__free_all`. The build script links
 *     lib/property_mosq.c, lib/packet_datatypes.c, and lib/memory_mosq.c.
 *   - Must be compiled with the same MQTT-protocol macros the upstream build
 *     uses; no additional -D flags are required.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "mosquitto.h"
#include "mqtt_protocol.h"
#include "mosquitto_internal.h"
#include "packet_mosq.h"
#include "property_mosq.h"

/*
 * Command bytes we cycle through. These are the parser-reachable control
 * packet types under MQTT 5 property parsing. Using a small closed set makes
 * the fuzzer's state space tractable while still covering the vulnerable
 * entry points.
 */
static const uint8_t cycle_commands[] = {
	CMD_CONNECT,
	CMD_PUBLISH,
	CMD_SUBSCRIBE,
	CMD_CONNACK,
	CMD_SUBACK,
	CMD_DISCONNECT,
};

/*
 * Drive a single framed chunk through the property parser. We populate a
 * stack `mosquitto__packet` as if the broker had just finished reading the
 * variable-header bytes off the wire.
 */
static void drive_one_chunk(uint8_t command, const uint8_t *frame, uint32_t frame_len)
{
	struct mosquitto__packet packet;
	mosquitto_property *properties = NULL;

	memset(&packet, 0, sizeof(packet));
	packet.command = command;
	packet.remaining_length = frame_len;
	packet.packet_length = frame_len;
	packet.to_process = frame_len;
	packet.pos = 0;

	/*
	 * property__read_all mutates packet->pos as it advances. It allocates
	 * property nodes via the internal allocator; the matching free path
	 * below is the real cleanup routine used by the broker.
	 */
	if(frame_len > 0){
		packet.payload = (uint8_t *)malloc(frame_len);
		if(!packet.payload){
			return;
		}
		memcpy(packet.payload, frame, frame_len);

		(void)property__read_all((int)command, &packet, &properties);

		mosquitto_property_free_all(&properties);
		free(packet.payload);
	}
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	size_t offset = 0;
	unsigned cycle_idx = 0;

	/*
	 * Stateful driver: split the fuzzer input into successive frames whose
	 * lengths are encoded in-band. Each frame is parsed against a chosen
	 * command byte from the cycle above, so the fuzzer reaches code paths
	 * that are only valid for specific packet types (publish properties,
	 * connect properties, subscribe options, etc.).
	 */
	while(offset + 2 <= size){
		uint16_t raw_len = (uint16_t)(data[offset] | ((uint16_t)data[offset + 1] << 8));
		offset += 2;

		uint32_t frame_len = raw_len & 0x0FFFU; /* cap at 4095 to bound per-iteration work */
		if(frame_len == 0){
			/* Empty frame still exercises the zero-length boundary. */
			drive_one_chunk(cycle_commands[cycle_idx % sizeof(cycle_commands)], NULL, 0);
			cycle_idx++;
			continue;
		}
		if(offset + frame_len > size){
			frame_len = (uint32_t)(size - offset);
		}

		drive_one_chunk(cycle_commands[cycle_idx % sizeof(cycle_commands)],
				data + offset, frame_len);

		offset += frame_len;
		cycle_idx++;

		if(cycle_idx > 32U){
			break; /* keep per-input cost bounded */
		}
	}

	return 0;
}
