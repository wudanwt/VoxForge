#ifndef TYPEMORE_C_SHERPA_SHIM_H
#define TYPEMORE_C_SHERPA_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TypeMoreSherpaRecognizer TypeMoreSherpaRecognizer;
typedef struct TypeMoreSherpaStreamSession TypeMoreSherpaStreamSession;

TypeMoreSherpaRecognizer *tm_sherpa_create_recognizer(
    const char *library_path,
    const char *encoder_path,
    const char *decoder_path,
    const char *tokens_path,
    const char *hotwords_path,
    int32_t num_threads,
    char *error_buffer,
    int32_t error_buffer_size);

TypeMoreSherpaStreamSession *tm_sherpa_create_stream_session(
    TypeMoreSherpaRecognizer *recognizer,
    char *error_buffer,
    int32_t error_buffer_size);

void tm_sherpa_accept_waveform(
    TypeMoreSherpaStreamSession *session,
    int32_t sample_rate,
    const float *samples,
    int32_t sample_count);

void tm_sherpa_finish(TypeMoreSherpaStreamSession *session);

int32_t tm_sherpa_copy_result(
    TypeMoreSherpaStreamSession *session,
    char *text_buffer,
    int32_t text_buffer_size);

const char *tm_sherpa_version(TypeMoreSherpaRecognizer *recognizer);

void tm_sherpa_destroy_stream_session(TypeMoreSherpaStreamSession *session);

void tm_sherpa_destroy_recognizer(TypeMoreSherpaRecognizer *recognizer);

#ifdef __cplusplus
}
#endif

#endif
