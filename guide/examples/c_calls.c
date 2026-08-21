#include <stddef.h>
#include <stdint.h>
#include "ultimate.h"
#include "uci.h"

static ultimate_capabilities caps;
static uci_request req;
static uint8_t bytes[512];
static char text[64];
static uint8_t byte_value;
static uint16_t word_value;
static uint32_t long_value;
static const char *message;

/* Compile every public call form printed in the C chapter. */
void guide_c_calls(void)
{
    byte_value = ultimate_init();
    byte_value = ultimate_available();
    byte_value = ultimate_detect(&caps);
    byte_value = ultimate_identify(UCI_TARGET_DOS1, text, sizeof text, &word_value);
    byte_value = ultimate_identify(UCI_TARGET_DOS1, text, sizeof text, NULL);
    byte_value = ultimate_get_model(text, sizeof text, &word_value);
    byte_value = ultimate_get_model(text, sizeof text, NULL);
    byte_value = ultimate_palette_get(bytes);
    byte_value = ultimate_palette_set(bytes);
    byte_value = ultimate_palette_set_color(0, 0, 0, 0);
    byte_value = ultimate_palette_reset();
    byte_value = ultimate_turbo_available();
    byte_value = ultimate_turbo_get();
    byte_value = ultimate_turbo_set(U64_SPEED_1MHZ);
    byte_value = ultimate_turbo_badlines(0);
    byte_value = ultimate_chdir(text);
    byte_value = ultimate_getpath(text, sizeof text, &word_value);
    byte_value = ultimate_getpath(text, sizeof text, NULL);
    byte_value = ultimate_opendir();
    byte_value = ultimate_readdir(text, sizeof text, &bytes[0]);
    byte_value = ultimate_readdir(text, sizeof text, NULL);
    byte_value = ultimate_open(text, DOS_FA_READ);
    byte_value = ultimate_close();
    byte_value = ultimate_read(bytes, sizeof bytes, &word_value);
    byte_value = ultimate_read(bytes, sizeof bytes, NULL);
    byte_value = ultimate_write(bytes, sizeof bytes);
    byte_value = ultimate_seek(long_value);
    byte_value = ultimate_delete(text);
    byte_value = ultimate_load(text, word_value);
    byte_value = ultimate_bload(text, word_value, word_value);
    byte_value = ultimate_save(text, word_value, word_value);
    word_value = ultimate_last_end();
    byte_value = ultimate_reu_available();
    word_value = ultimate_reu_size();
    byte_value = ultimate_reu_stash(word_value, long_value, word_value);
    byte_value = ultimate_reu_fetch(word_value, long_value, word_value);
    byte_value = ultimate_reu_load(long_value, long_value);
    byte_value = ultimate_reu_save(long_value, long_value);
    byte_value = ultimate_net_ifcount(&byte_value);
    byte_value = ultimate_net_macaddr(0, bytes);
    byte_value = ultimate_net_ipconfig(0, bytes);
    byte_value = ultimate_net_connect(text, word_value, &byte_value);
    byte_value = ultimate_net_udp(text, word_value, &byte_value);
    byte_value = ultimate_net_close(byte_value);
    byte_value = ultimate_net_read(byte_value, bytes, sizeof bytes, &word_value);
    byte_value = ultimate_net_write(byte_value, bytes, sizeof bytes, &word_value);
    byte_value = ultimate_http_get(text, bytes, sizeof bytes, &word_value);
    byte_value = ultimate_http_open(HTTP_VERB_GET, text, &byte_value);
    byte_value = ultimate_http_header(byte_value, text);
    byte_value = ultimate_http_exchange(byte_value, HTTP_BODY_NONE,
                                        bytes, sizeof bytes, &word_value);
    byte_value = ultimate_http_close(byte_value);
    byte_value = ultimate_http_free_all();
    message = ultimate_strerror(byte_value);
    word_value = ultimate_device_code();

    byte_value = uci_signature_present();
    byte_value = uci_ident_register();
    byte_value = uci_init();
    byte_value = uci_exec(&req);
    byte_value = uci_exec_first(&req);
    byte_value = uci_exec_next(&req);
    byte_value = uci_more_blocks();
    byte_value = uci_abort();
    uci_set_timeout(byte_value);
    byte_value = uci_get_timeout();
    word_value = uci_last_device_code();
    byte_value = uci_status_format(UCI_TARGET_DOS1);
    byte_value = uci_decode_status(UCI_TARGET_DOS1, bytes, sizeof bytes);

    (void)message;
}
