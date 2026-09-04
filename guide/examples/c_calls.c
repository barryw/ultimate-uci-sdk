#include <stddef.h>
#include <stdint.h>
#include "ultimate.h"
#include "uci.h"

static ultimate_capabilities caps;
static ultimate_sid_info sid_info;
static uci_request req;
static uint8_t bytes[512];
static char text[64];
static uint8_t byte_value;
static uint8_t index;
static uint8_t request_handle;
static uint16_t word_value;
static uint32_t long_value;
static int32_t signed_value;
static const char *message;
static ultimate_fileinfo fileinfo;
static ultimate_drives drives;
static ultimate_audio_voice voice;
static ultimate_vsprite vsprite;
static const uint8_t vsprite_image[8] = {
    0x18, 0x3c, 0x7e, 0xff, 0xff, 0x7e, 0x3c, 0x18
};
static const uint8_t vsprite_mask[8] = {
    0xe7, 0xc3, 0x81, 0x00, 0x00, 0x81, 0xc3, 0xe7
};
static const uint8_t http_verbs[] = {
    HTTP_VERB_GET, HTTP_VERB_PUT, HTTP_VERB_POST, HTTP_VERB_PATCH,
    HTTP_VERB_DELETE, HTTP_VERB_HEAD, HTTP_VERB_OPTIONS,
    HTTP_VERB_CONNECT, HTTP_VERB_TRACE
};

/* Compile every public call form printed in the C chapter. */
void guide_c_calls(void)
{
    req.target = UCI_TARGET_DOS1;
    req.command = UCI_CMD_IDENTIFY;
    req.args = NULL;
    req.arglen = 0;
    req.payload = NULL;
    req.payloadlen = 0;
    req.data = bytes;
    req.datamax = sizeof bytes;
    req.status = NULL;
    req.statusmax = 0;

    vsprite.bitmap = (uint8_t *)0xe000;
    vsprite.source = vsprite_image;
    vsprite.mask = vsprite_mask;
    vsprite.screen = (uint8_t *)0xcc00;
    vsprite.x = 18;
    vsprite.y = 80;
    vsprite.width = 1;
    vsprite.height = 8;
    vsprite.color = 2;

    voice.channel = 0;
    voice.volume = UA_VOLUME_MAX;
    voice.reu_address = 0x4000UL;
    voice.length = 8000UL;
    voice.repeat_a = 0;
    voice.repeat_b = 0;
    voice.rate = 781;

    byte_value = ultimate_init();
    byte_value = ultimate_available();
    byte_value = ultimate_detect(&caps);
    byte_value = ultimate_identify(UCI_TARGET_DOS1, text, sizeof text, &word_value);
    byte_value = ultimate_identify(UCI_TARGET_DOS1, text, sizeof text, NULL);
    byte_value = ultimate_get_model(text, sizeof text, &word_value);
    byte_value = ultimate_get_model(text, sizeof text, NULL);
    byte_value = ultimate_legacy_get_sid_info(&sid_info);
    byte_value = ultimate_palette_get(bytes);
    byte_value = ultimate_palette_set(bytes);
    byte_value = ultimate_palette_set_color(0, 0, 0, 0);
    byte_value = ultimate_palette_reset();
    byte_value = ultimate_turbo_available();
    byte_value = ultimate_turbo_get();
    byte_value = ultimate_turbo_set(U64_SPEED_1MHZ);
    byte_value = ultimate_turbo_set(U64_SPEED_2MHZ);
    byte_value = ultimate_turbo_set(U64_SPEED_3MHZ);
    byte_value = ultimate_turbo_set(U64_SPEED_4MHZ);
    byte_value = ultimate_turbo_set(U64_SPEED_MAX);
    byte_value = ultimate_turbo_badlines(0);
    vsprite.flags = 0;
    byte_value = ultimate_vsprite_draw(&vsprite);
    vsprite.flags = VSPRITE_F_MASKED;
    byte_value = ultimate_vsprite_draw(&vsprite);
    vsprite.flags = VSPRITE_F_COPY;
    byte_value = ultimate_vsprite_draw(&vsprite);
    vsprite.flags = VSPRITE_F_COLOR;
    byte_value = ultimate_vsprite_draw(&vsprite);
    byte_value = ultimate_chdir(text);
    byte_value = ultimate_getpath(text, sizeof text, &word_value);
    byte_value = ultimate_getpath(text, sizeof text, NULL);
    byte_value = ultimate_opendir();
    byte_value = ultimate_readdir(text, sizeof text, &bytes[0]);
    byte_value = ultimate_readdir(text, sizeof text, NULL);
    byte_value = ultimate_open(text, DOS_FA_READ);
    byte_value = ultimate_open(text, DOS_FA_WRITE);
    byte_value = ultimate_open(text, DOS_FA_WRITE | DOS_FA_CREATE_NEW);
    byte_value = ultimate_open(text, DOS_FA_WRITE | DOS_FA_CREATE_ALWAYS);
    byte_value = ultimate_open(text, DOS_FA_READ | DOS_FA_WRITE);
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
    byte_value = ultimate_audio_init();
    byte_value = ultimate_audio_available();
    byte_value = ultimate_audio_version();
    byte_value = ultimate_audio_load_wav(text, long_value, &voice);
    voice.flags = 0;
    voice.pan = UA_PAN_LEFT;
    byte_value = ultimate_audio_configure(&voice);
    voice.flags = UA_CTRL_16BIT;
    voice.pan = UA_PAN_CENTER;
    byte_value = ultimate_audio_configure(&voice);
    voice.flags = UA_CTRL_INTERLEAVE;
    byte_value = ultimate_audio_configure(&voice);
    voice.flags = UA_CTRL_16BIT | UA_CTRL_INTERLEAVE | UA_CTRL_REPEAT;
    voice.pan = UA_PAN_RIGHT;
    byte_value = ultimate_audio_configure(&voice);
    byte_value = ultimate_audio_start(voice.channel, voice.flags);
    byte_value = ultimate_audio_irq_status();
    byte_value = ultimate_audio_irq_clear(voice.channel);
    byte_value = ultimate_audio_stop(voice.channel);
    byte_value = ultimate_stat(text, &fileinfo);
    byte_value = ultimate_fstat(&fileinfo);
    byte_value = ultimate_rename(text, text);
    byte_value = ultimate_copy(text, text);
    byte_value = ultimate_mkdir(text);
    byte_value = ultimate_home();
    byte_value = ultimate_mount(8, text);
    byte_value = ultimate_mount(ULTIMATE_DRIVE_LAST, text);
    byte_value = ultimate_unmount(8);
    byte_value = ultimate_swap(8);
    byte_value = ultimate_get_time(ULTIMATE_TIME_PLAIN, text,
                                   sizeof text, &word_value);
    byte_value = ultimate_get_time(ULTIMATE_TIME_WEEKDAY, text,
                                   sizeof text, NULL);
    byte_value = ultimate_set_time(126, 8, 22, 14, 30, 0);
    byte_value = ultimate_drive_info(&drives);
    byte_value = ultimate_drive_enable(ULTIMATE_DRIVE_A, 1);
    byte_value = ultimate_drive_enable(ULTIMATE_DRIVE_B, 0);
    byte_value = ultimate_drive_power(ULTIMATE_DRIVE_A, &byte_value);
    byte_value = ultimate_ramdisk_info(bytes);
    byte_value = ultimate_freeze();
    byte_value = ultimate_reboot();
    byte_value = ultimate_net_ifcount(&byte_value);
    byte_value = ultimate_net_macaddr(0, bytes);
    byte_value = ultimate_net_ipconfig(0, bytes);
    byte_value = ultimate_net_setip(0, bytes);
    byte_value = ultimate_net_connect(text, word_value, &byte_value);
    byte_value = ultimate_net_udp(text, word_value, &byte_value);
    byte_value = ultimate_net_close(byte_value);
    byte_value = ultimate_net_read(byte_value, bytes, sizeof bytes, &word_value);
    byte_value = ultimate_net_write(byte_value, bytes, sizeof bytes, &word_value);
    byte_value = ultimate_http_get(text, bytes, sizeof bytes, &word_value);
    for (index = 0; index < sizeof http_verbs; ++index) {
        byte_value = ultimate_http_open(http_verbs[index], text,
                                        &request_handle);
        byte_value = ultimate_http_close(request_handle);
    }
    byte_value = ultimate_http_header(byte_value, text);
    byte_value = ultimate_http_exchange(byte_value, HTTP_BODY_NONE,
                                        bytes, sizeof bytes, &word_value);
    byte_value = ultimate_http_close(byte_value);
    byte_value = ultimate_http_body(HTTP_BODY_JSON_OBJECT, &byte_value);
    byte_value = ultimate_http_body(HTTP_BODY_JSON_ARRAY, &byte_value);
    byte_value = ultimate_http_body(HTTP_BODY_URL_ENCODED, &byte_value);
    byte_value = ultimate_http_body(HTTP_BODY_BINARY, &byte_value);
    byte_value = ultimate_http_body_string(byte_value, text, text);
    byte_value = ultimate_http_body_int(byte_value, text, signed_value);
    byte_value = ultimate_http_body_bool(byte_value, text, 1);
    byte_value = ultimate_http_body_object(byte_value, text);
    byte_value = ultimate_http_body_array(byte_value, text);
    byte_value = ultimate_http_body_up(byte_value);
    byte_value = ultimate_http_body_binary(byte_value, bytes, sizeof bytes);
    byte_value = ultimate_http_body_clear(byte_value);
    byte_value = ultimate_http_body_free(byte_value);
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
