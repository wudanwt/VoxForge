#ifndef TYPEMORE_C_SHERPA_SHIM_H
#define TYPEMORE_C_SHERPA_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TypeMoreSherpaSession TypeMoreSherpaSession;

TypeMoreSherpaSession *tm_sherpa_create(
    const char *library_path,
    const char *encoder_path,
    const char *decoder_path,
    const char *tokens_path,
    const char *hotwords_path,
    int32_t num_threads,
    char *error_buffer,
    int32_t error_buffer_size);

void tm_sherpa_accept_waveform(
    TypeMoreSherpaSession *session,
    int32_t sample_rate,
    const float *samples,
    int32_t sample_count);

void tm_sherpa_finish(TypeMoreSherpaSession *session);

int32_t tm_sherpa_copy_result(
    TypeMoreSherpaSession *session,
    char *text_buffer,
    int32_t text_buffer_size);

const char *tm_sherpa_version(TypeMoreSherpaSession *session);

void tm_sherpa_destroy(TypeMoreSherpaSession *session);

#ifdef __cplusplus
}
#endif

#endif
