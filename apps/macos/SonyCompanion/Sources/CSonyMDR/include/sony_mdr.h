#ifndef SONY_MDR_H
#define SONY_MDR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t *data;
    size_t len;
    size_t cap;
} MdrBuffer;

typedef struct {
    uint8_t state;
    int16_t battery_level;
    int16_t battery_charging;
    int16_t nc_enabled;
    int16_t nc_mode;
    int16_t ambient_mode;
    int16_t ambient_level;
    uint64_t revision;
    uint8_t pending_write;
    /* 1 when noise-control state has actually been received. */
    uint8_t nc_known;
    /* Noise adaptation (auto ambient) and its sensitivity step. */
    uint8_t nc_adaptation;
    uint8_t nc_sensitivity;
    uint32_t protocol_version;
    uint8_t supports_table1;
    uint8_t supports_table2;
    /* Model name and firmware reported by the device, NUL-terminated. */
    char model[48];
    char firmware[48];
    /* Equaliser. eq_known gates every other eq_* field. */
    uint8_t eq_known;
    uint8_t eq_enabled;
    uint8_t eq_preset;
    uint8_t eq_band_count;
    uint8_t eq_band_step;
    uint8_t eq_band_len;
    uint8_t eq_bands[16];
    int16_t clear_bass;
    int16_t clear_bass_min;
    int16_t clear_bass_max;
    uint16_t eq_preset_count;
    /* Audio upscaling (DSEE-family). */
    uint8_t upscaling_known;
    uint8_t upscaling_enabled;
    /* Negotiated codec, e.g. "AAC". */
    char codec[16];
    /* Auto power off (read-only) and connection mode flags. */
    uint8_t apo_known;
    uint8_t apo_enabled;
    uint8_t conn_known;
    uint8_t conn_classic;
    uint8_t conn_le;
    /* Table-2 peripheral/power: music hand-over, USB submersion. */
    uint8_t mho_known;
    uint8_t mho_enabled;
    uint8_t usb_known;
    uint8_t usb_submerged;
    /* Playback controller: known, enabled, state, source. */
    uint8_t play_known;
    uint8_t play_enabled;
    uint8_t play_state;
    uint8_t play_source;
    /* Wearing detection: known flag, enabled, worn, count, result code. */
    uint8_t wear_known;
    uint8_t wear_detection_enabled;
    uint8_t wear_worn;
    uint8_t wear_selected_earpieces;
    uint8_t wear_result_code;
    /* Auto power off with wearing detection: (current, last) element. */
    uint8_t apow_known;
    uint8_t apow_current;
    uint8_t apow_last;
    uint8_t apow_enabled_known;
    uint8_t apow_enabled;
    /* Listening mode: known flag, 0 standard / 1 BGM / 2 cinema, room size. */
    uint8_t listen_known;
    uint8_t listen_mode;
    uint8_t listen_room;
    /* Music volume: known flag, advertised steps, current value. */
    uint8_t volume_known;
    uint8_t volume_steps;
    uint8_t volume;
    /* Call volume, same gating. */
    uint8_t call_volume_known;
    uint8_t call_volume_steps;
    uint8_t call_volume;
    /* Auto volume with limitation (read-only). */
    uint8_t auto_volume_known;
    uint8_t auto_volume_enabled;
    /* Auto standby candidate and on/off setting. */
    uint8_t auto_standby_known;
    uint8_t auto_standby_available;
    uint8_t auto_standby_setting_known;
    uint8_t auto_standby_setting;
    /* Speak-to-Chat: known, enabled, effect, sensitivity, auto-off time. */
    uint8_t st_known;
    uint8_t st_enabled;
    uint8_t st_effect;
    uint8_t st_sensitivity;
    uint8_t st_mode_out;
    /* Head gesture on/off. */
    uint8_t hg_known;
    uint8_t hg_enabled;
    /* Safe-volume WHO level. */
    uint8_t safe_volume_known;
    uint8_t safe_volume_level;
    /* Adaptive control started. */
    uint8_t ac_known;
    uint8_t ac_started;
    /* Quick Access function ids. */
    uint8_t qa_known;
    uint8_t qa_count;
    uint8_t qa0;
    uint8_t qa1;
    /* Control by wearing. */
    uint8_t cbw_known;
    uint8_t cbw_enabled;
    /* Mic on/off. */
    uint8_t mic_known;
    uint8_t mic_enabled;
    /* Sony Voice Assistant. */
    uint8_t sva_known;
    uint8_t sva_enabled;
    uint8_t sval_known;
    uint8_t sval_language;
    /* Voice guidance. */
    uint8_t vg_known;
    uint8_t vg_enabled;
    uint8_t vgv_known;
    int8_t vgv_volume;
    /* Head gesture training. */
    uint8_t hgt_known;
    uint8_t hgt_in_test;
    uint8_t hgt_enabled;
    uint8_t hga_known;
    uint8_t hga_action;
    /* Paired-device management (table-2 PERI type 0x00/0x02). */
    uint8_t pair_known;
    uint8_t pair_count;
    uint8_t pair_connected_count;
    uint8_t pair_playback_device;
} MdrSnapshot;

typedef enum {
    MDR_OK = 0,
    MDR_NULL_HANDLE = 1,
    MDR_NOT_READY = 2,
    MDR_NO_DATA = 3,
} MdrStatus;

void *mdr_session_new(void);
void mdr_session_free(void *handle);

/* Begin the handshake. `now_ms` starts the command timer. */
MdrStatus mdr_connect(void *handle, uint64_t now_ms, MdrBuffer *out);

/* Feed received bytes. Outbound frames (acknowledgements, the next command)
   are returned in `out`, possibly several concatenated. */
MdrStatus mdr_receive(void *handle, const uint8_t *data, size_t len, uint64_t now_ms, MdrBuffer *out);

/* MDR_NOT_READY: the session is not ready yet.
   MDR_NO_DATA:   the request was queued behind an outstanding command and
                  will be sent when that command is acknowledged. */
MdrStatus mdr_request_battery(void *handle, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_set_noise_control(void *handle, bool enabled, uint8_t mode, uint8_t ambient_mode,
                                uint8_t ambient_level, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_snapshot(void *handle, MdrSnapshot *out);
MdrStatus mdr_poll(void *handle, uint64_t now_ms, MdrBuffer *out);

/* Number of queued or in-flight commands. */
size_t mdr_pending_count(void *handle);

/* Diagnostic: queue an arbitrary payload on a ready session. */
MdrStatus mdr_send_raw(void *handle, const uint8_t *data, size_t len, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_send_raw_table(void *handle, uint8_t table, const uint8_t *data, size_t len,
                             uint64_t now_ms, MdrBuffer *out);

/* Equaliser. Presets are enumerated with the two calls below; `mdr_eq_set_preset`
   refuses a preset the device did not advertise. */
MdrStatus mdr_eq_preset_count(void *handle, size_t *out_count);
MdrStatus mdr_eq_preset_at(void *handle, size_t index, uint8_t *out_id, char *name, size_t name_cap);
MdrStatus mdr_eq_set_preset(void *handle, uint8_t preset, const uint8_t *bands,
                            size_t band_count, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_eq_set_clear_bass(void *handle, int8_t level, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_set_upscaling(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_set_auto_power_off_wearing(void *handle, uint8_t current, uint8_t last,
                                         uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_playback_control(void *handle, uint8_t control, uint64_t now_ms, MdrBuffer *out);
/* Listening mode: 0 standard, 1 BGM, 2 cinema. */
MdrStatus mdr_set_listening_mode(void *handle, uint8_t mode, uint64_t now_ms, MdrBuffer *out);
/* Table-2 music hand-over setting. */
MdrStatus mdr_set_music_hand_over(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
/* Music volume, clamped to the device's advertised steps. */
MdrStatus mdr_set_music_volume(void *handle, uint8_t volume, uint64_t now_ms, MdrBuffer *out);
/* Call volume, clamped to the device's advertised steps. */
MdrStatus mdr_set_call_volume(void *handle, uint8_t volume, uint64_t now_ms, MdrBuffer *out);
/* Auto standby on/off (table-2 POWER type 0x00). */
MdrStatus mdr_set_auto_standby(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
/* Set one general-setting boolean slot. */
MdrStatus mdr_set_gs_boolean(void *handle, uint8_t gs_type, bool on, uint64_t now_ms,
                             MdrBuffer *out);
/* Start or stop adaptive control. */
MdrStatus mdr_set_adaptive_control(void *handle, bool start, uint64_t now_ms, MdrBuffer *out);
/* Replace the Quick Access function list. */
MdrStatus mdr_set_quick_access_functions(void *handle, const uint8_t *data, size_t len,
                                         uint64_t now_ms, MdrBuffer *out);
/* Playback control by wearing/removing the headphones. */
MdrStatus mdr_set_control_by_wearing(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
/* Mic on/off by headphone operation. */
MdrStatus mdr_set_mic_on_off(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
/* Sony Voice Assistant on/off. */
MdrStatus mdr_set_sony_voice_assistant(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
/* Voice guidance on/off and volume. */
MdrStatus mdr_set_voice_guidance(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_set_voice_guidance_volume(void *handle, int8_t volume, uint64_t now_ms, MdrBuffer *out);
/* Start or finish head gesture training. */
MdrStatus mdr_set_head_gesture_training(void *handle, bool start, uint64_t now_ms, MdrBuffer *out);
/* Safe-volume WHO standard level: 0 normal, 1 sensitive. */
MdrStatus mdr_set_safe_volume(void *handle, uint8_t level, uint64_t now_ms, MdrBuffer *out);
/* Head gesture on/off. */
MdrStatus mdr_set_head_gesture(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
/* User power off. */
MdrStatus mdr_power_off(void *handle, uint64_t now_ms, MdrBuffer *out);
/* Speak-to-Chat on/off and detail. */
MdrStatus mdr_set_smart_talking(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_set_smart_talking_detail(void *handle, uint8_t sensitivity, uint8_t mode_out,
                                       uint64_t now_ms, MdrBuffer *out);
/* JSON snapshot; returns bytes written, or a negative required size. */
intptr_t mdr_state_json(void *handle, char *buf, size_t cap);

/* General settings: the device names each slot (sidetone, multipoint, touch
   panel…), so they are enumerated rather than hard-coded. */
MdrStatus mdr_gs_count(void *handle, size_t *out_count);
MdrStatus mdr_gs_at(void *handle, size_t index, uint8_t *out_type, uint8_t *out_known,
                    uint8_t *out_value, char *title, size_t title_cap,
                    char *detail, size_t detail_cap);
MdrStatus mdr_set_gs_setting(void *handle, uint8_t gs_type, bool enabled,
                             uint64_t now_ms, MdrBuffer *out);

/* Functions the device advertises as supported. */
MdrStatus mdr_supported_count(void *handle, size_t *out_count);
MdrStatus mdr_supported_at(void *handle, size_t index, uint8_t *out_value,
                           char *name, size_t name_cap);
/* First PresetEqErrorCodeType for an equaliser the device has off
   (2 = listening mode); -1 when it is on or gave no reason. */
MdrStatus mdr_eq_error_code(void *handle, int32_t *out_code);
/* ModelSeries and ModelColor bytes from SERIES_AND_COLOR_INFO; -1 until
   the device has answered. */
MdrStatus mdr_model_color(void *handle, int32_t *out_series, int32_t *out_color);
/* Table-2 support list; bytes are named with the table-2 enum. */
MdrStatus mdr_supported_count_table2(void *handle, size_t *out_count);
MdrStatus mdr_supported_at_table2(void *handle, size_t index, uint8_t *out_value,
                                  char *name, size_t name_cap);

/* Paired Classic Bluetooth devices (table-2 pairing management). */
MdrStatus mdr_paired_count(void *handle, size_t *out_count);
MdrStatus mdr_paired_at(void *handle, size_t index, uint8_t *out_connected,
                        uint8_t *out_cod_known, uint32_t *out_cod,
                        char *address, size_t address_cap,
                        char *name, size_t name_cap);
MdrStatus mdr_pairing_capability(void *handle, uint8_t *out_max_paired,
                                 uint8_t *out_max_connected,
                                 uint8_t *out_file_transfer);
MdrStatus mdr_pairing_connect(void *handle, size_t index, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_pairing_disconnect(void *handle, size_t index, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_pairing_set_mode(void *handle, bool pairing, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_pairing_event(void *handle, uint8_t *out_action, uint8_t *out_result,
                            char *address, size_t address_cap);
MdrStatus mdr_pairing_mode(void *handle, uint8_t *out_mode, uint8_t *out_enabled);

/* Voice assistant: current assignment plus the assistants it supports. */
MdrStatus mdr_va_state(void *handle, uint8_t *out_current, size_t *out_count);
MdrStatus mdr_va_at(void *handle, size_t index, uint8_t *out_value,
                    char *name, size_t name_cap);
MdrStatus mdr_set_voice_assistant(void *handle, uint8_t value, uint64_t now_ms, MdrBuffer *out);
MdrStatus mdr_set_nc_adaptation(void *handle, bool enabled, uint64_t now_ms, MdrBuffer *out);

void mdr_bytes_free(MdrBuffer *buf);
const char *mdr_version(void);

#ifdef __cplusplus
}
#endif

#endif /* SONY_MDR_H */
