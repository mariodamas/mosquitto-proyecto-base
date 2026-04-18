/*
 * libwebsockets - small server side websockets and web server implementation
 *
 * Copyright (C) 2010-2018 Andy Green <andy@warmcat.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation:
 * version 2.1 of the License.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA  02110-1301  USA
 *
 * Vendored for lab purposes from:
 *   https://github.com/warmcat/libwebsockets/archive/v2.4.2.tar.gz
 * Upstream tag: v2.4.2
 */

#ifndef LIBWEBSOCKET_H_3060898B846849FF9F88F5DB59B5950C
#define LIBWEBSOCKET_H_3060898B846849FF9F88F5DB59B5950C

#ifdef __cplusplus
#include <cstddef>
#include <cstdarg>
#else
#include <stddef.h>
#include <stdarg.h>
#endif

#include <stdint.h>

/* Version information */
#define LWS_LIBRARY_VERSION_MAJOR 2
#define LWS_LIBRARY_VERSION_MINOR 4
#define LWS_LIBRARY_VERSION_PATCH 2
#define LWS_LIBRARY_VERSION_PATCH_ELABORATED 2
#define LWS_LIBRARY_VERSION "2.4.2"
#define LWS_LIBRARY_VERSION_NUMBER 2004002

/* Build options captured at configure time */
#define LWS_MAX_SMP 1
#define LWS_SEND_BUFFER_PRE_PADDING 0

struct lws;
struct lws_context;
struct lws_plat_file_ops;

typedef int64_t lws_filepos_t;
typedef int64_t lws_fileofs_t;
typedef uint32_t lws_fop_flags_t;

/** enum lws_log_levels - log levels */
enum lws_log_levels {
    LLL_ERR   = 1 << 0,
    LLL_WARN  = 1 << 1,
    LLL_NOTICE= 1 << 2,
    LLL_INFO  = 1 << 3,
    LLL_DEBUG = 1 << 4,
    LLL_PARSER= 1 << 5,
    LLL_HEADER= 1 << 6,
    LLL_EXT   = 1 << 7,
    LLL_CLIENT= 1 << 8,
    LLL_LATENCY= 1 << 9,
    LLL_COUNT = 10 /* set to count of valid flags */
};

LWS_VISIBLE LWS_EXTERN void _lws_log(int filter, const char *format, ...);
LWS_VISIBLE LWS_EXTERN void _lws_logv(int filter, const char *format, va_list vl);

struct lws_context_creation_info {
    int port;
    const char *iface;
    const struct lws_protocols *protocols;
    const struct lws_extension *extensions;
    const struct lws_token_limits *token_limits;
    const char *ssl_cert_filepath;
    const char *ssl_private_key_filepath;
    const char *ssl_ca_filepath;
    const char *ssl_cipher_list;
    const char *http_proxy_address;
    unsigned int http_proxy_port;
    int gid;
    int uid;
    unsigned int options;
    void *user;
    int ka_time;
    int ka_probes;
    int ka_interval;
    unsigned int timeout_secs;
    const char *ecdh_curve;
    const char *vhost_name;
    const char * const *plugin_dirs;
    const struct lws_protocol_vhost_options *pvo;
    int keepalive_timeout;
    const char *log_filepath;
    const struct lws_http_mount *mounts;
    const char *server_string;
    unsigned int pt_serv_buf_size;
    int max_http_header_data2;
    long ssl_options_set;
    long ssl_options_clear;
    unsigned short ws_ping_pong_interval;
    const struct lws_protocol_vhost_options *headers;
    const struct lws_protocol_vhost_options *reject_service_keywords;
    void *external_baggage_free_on_destroy;
    const struct lws_token_limits *_a[2];
    unsigned int count_threads;
    unsigned int fd_limit_per_thread;
    unsigned int timeout_secs_ah_idle;
    sockaddr_in6 *listen_obj;
    lws_system_ops_t *system_ops;
    const lws_retry_bo_t *retry_and_idle_policy;
};

LWS_VISIBLE LWS_EXTERN struct lws_context *
lws_create_context(struct lws_context_creation_info *info);

LWS_VISIBLE LWS_EXTERN void
lws_context_destroy(struct lws_context *context);

LWS_VISIBLE LWS_EXTERN int
lws_service(struct lws_context *context, int timeout_ms);

#endif /* LIBWEBSOCKET_H_3060898B846849FF9F88F5DB59B5950C */
