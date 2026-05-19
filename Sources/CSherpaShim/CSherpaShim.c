#include "CSherpaShim.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct SherpaOnnxOnlineTransducerModelConfig {
    const char *encoder;
    const char *decoder;
    const char *joiner;
} SherpaOnnxOnlineTransducerModelConfig;

typedef struct SherpaOnnxOnlineParaformerModelConfig {
    const char *encoder;
    const char *decoder;
} SherpaOnnxOnlineParaformerModelConfig;

typedef struct SherpaOnnxOnlineZipformer2CtcModelConfig {
    const char *model;
} SherpaOnnxOnlineZipformer2CtcModelConfig;

typedef struct SherpaOnnxOnlineNemoCtcModelConfig {
    const char *model;
} SherpaOnnxOnlineNemoCtcModelConfig;

typedef struct SherpaOnnxOnlineToneCtcModelConfig {
    const char *model;
} SherpaOnnxOnlineToneCtcModelConfig;

typedef struct SherpaOnnxOnlineModelConfig {
    SherpaOnnxOnlineTransducerModelConfig transducer;
    SherpaOnnxOnlineParaformerModelConfig paraformer;
    SherpaOnnxOnlineZipformer2CtcModelConfig zipformer2_ctc;
    const char *tokens;
    int32_t num_threads;
    const char *provider;
    int32_t debug;
    const char *model_type;
    const char *modeling_unit;
    const char *bpe_vocab;
    const char *tokens_buf;
    int32_t tokens_buf_size;
    SherpaOnnxOnlineNemoCtcModelConfig nemo_ctc;
    SherpaOnnxOnlineToneCtcModelConfig t_one_ctc;
} SherpaOnnxOnlineModelConfig;

typedef struct SherpaOnnxFeatureConfig {
    int32_t sample_rate;
    int32_t feature_dim;
} SherpaOnnxFeatureConfig;

typedef struct SherpaOnnxOnlineCtcFstDecoderConfig {
    const char *graph;
    int32_t max_active;
} SherpaOnnxOnlineCtcFstDecoderConfig;

typedef struct SherpaOnnxHomophoneReplacerConfig {
    const char *dict_dir;
    const char *lexicon;
    const char *rule_fsts;
} SherpaOnnxHomophoneReplacerConfig;

typedef struct SherpaOnnxOnlineRecognizerConfig {
    SherpaOnnxFeatureConfig feat_config;
    SherpaOnnxOnlineModelConfig model_config;
    const char *decoding_method;
    int32_t max_active_paths;
    int32_t enable_endpoint;
    float rule1_min_trailing_silence;
    float rule2_min_trailing_silence;
    float rule3_min_utterance_length;
    const char *hotwords_file;
    float hotwords_score;
    SherpaOnnxOnlineCtcFstDecoderConfig ctc_fst_decoder_config;
    const char *rule_fsts;
    const char *rule_fars;
    float blank_penalty;
    const char *hotwords_buf;
    int32_t hotwords_buf_size;
    SherpaOnnxHomophoneReplacerConfig hr;
} SherpaOnnxOnlineRecognizerConfig;

typedef struct SherpaOnnxOnlineRecognizerResult {
    const char *text;
    const char *tokens;
    const char *const *tokens_arr;
    float *timestamps;
    int32_t count;
    const char *json;
} SherpaOnnxOnlineRecognizerResult;

typedef struct SherpaOnnxOnlineRecognizer SherpaOnnxOnlineRecognizer;
typedef struct SherpaOnnxOnlineStream SherpaOnnxOnlineStream;

typedef const char *(*FnGetVersionStr)(void);
typedef const SherpaOnnxOnlineRecognizer *(*FnCreateRecognizer)(const SherpaOnnxOnlineRecognizerConfig *);
typedef void (*FnDestroyRecognizer)(const SherpaOnnxOnlineRecognizer *);
typedef const SherpaOnnxOnlineStream *(*FnCreateStream)(const SherpaOnnxOnlineRecognizer *);
typedef void (*FnDestroyStream)(const SherpaOnnxOnlineStream *);
typedef void (*FnAcceptWaveform)(const SherpaOnnxOnlineStream *, int32_t, const float *, int32_t);
typedef int32_t (*FnIsReady)(const SherpaOnnxOnlineRecognizer *, const SherpaOnnxOnlineStream *);
typedef void (*FnDecode)(const SherpaOnnxOnlineRecognizer *, const SherpaOnnxOnlineStream *);
typedef const SherpaOnnxOnlineRecognizerResult *(*FnGetResult)(const SherpaOnnxOnlineRecognizer *, const SherpaOnnxOnlineStream *);
typedef void (*FnDestroyResult)(const SherpaOnnxOnlineRecognizerResult *);
typedef void (*FnInputFinished)(const SherpaOnnxOnlineStream *);
typedef void (*FnSetOption)(const SherpaOnnxOnlineStream *, const char *, const char *);

struct TypeMoreSherpaSession {
    void *library_handle;
    const SherpaOnnxOnlineRecognizer *recognizer;
    const SherpaOnnxOnlineStream *stream;
    FnGetVersionStr get_version;
    FnDestroyRecognizer destroy_recognizer;
    FnDestroyStream destroy_stream;
    FnAcceptWaveform accept_waveform;
    FnIsReady is_ready;
    FnDecode decode;
    FnGetResult get_result;
    FnDestroyResult destroy_result;
    FnInputFinished input_finished;
    FnSetOption set_option;
};

static void tm_set_error(char *buffer, int32_t size, const char *message) {
    if (buffer == NULL || size <= 0) {
        return;
    }
    snprintf(buffer, (size_t)size, "%s", message == NULL ? "unknown sherpa error" : message);
}

static void *tm_symbol(void *handle, const char *name, char *error, int32_t error_size) {
    void *symbol = dlsym(handle, name);
    if (symbol == NULL) {
        char message[512];
        snprintf(message, sizeof(message), "缺少 sherpa-onnx C API 符号：%s", name);
        tm_set_error(error, error_size, message);
    }
    return symbol;
}

static void tm_decode_ready(TypeMoreSherpaSession *session) {
    if (session == NULL || session->recognizer == NULL || session->stream == NULL) {
        return;
    }
    while (session->is_ready(session->recognizer, session->stream)) {
        session->decode(session->recognizer, session->stream);
    }
}

TypeMoreSherpaSession *tm_sherpa_create(
    const char *library_path,
    const char *encoder_path,
    const char *decoder_path,
    const char *tokens_path,
    const char *hotwords_path,
    int32_t num_threads,
    char *error_buffer,
    int32_t error_buffer_size) {
    if (library_path == NULL || strlen(library_path) == 0) {
        tm_set_error(error_buffer, error_buffer_size, "未找到 sherpa-onnx 动态库路径。");
        return NULL;
    }

    void *library = dlopen(library_path, RTLD_NOW | RTLD_GLOBAL);
    if (library == NULL) {
        const char *dl_error = dlerror();
        char message[1024];
        snprintf(message, sizeof(message), "无法加载 sherpa-onnx 动态库：%s", dl_error == NULL ? library_path : dl_error);
        tm_set_error(error_buffer, error_buffer_size, message);
        return NULL;
    }

    FnGetVersionStr get_version = (FnGetVersionStr)tm_symbol(library, "SherpaOnnxGetVersionStr", error_buffer, error_buffer_size);
    FnCreateRecognizer create_recognizer = (FnCreateRecognizer)tm_symbol(library, "SherpaOnnxCreateOnlineRecognizer", error_buffer, error_buffer_size);
    FnDestroyRecognizer destroy_recognizer = (FnDestroyRecognizer)tm_symbol(library, "SherpaOnnxDestroyOnlineRecognizer", error_buffer, error_buffer_size);
    FnCreateStream create_stream = (FnCreateStream)tm_symbol(library, "SherpaOnnxCreateOnlineStream", error_buffer, error_buffer_size);
    FnDestroyStream destroy_stream = (FnDestroyStream)tm_symbol(library, "SherpaOnnxDestroyOnlineStream", error_buffer, error_buffer_size);
    FnAcceptWaveform accept_waveform = (FnAcceptWaveform)tm_symbol(library, "SherpaOnnxOnlineStreamAcceptWaveform", error_buffer, error_buffer_size);
    FnIsReady is_ready = (FnIsReady)tm_symbol(library, "SherpaOnnxIsOnlineStreamReady", error_buffer, error_buffer_size);
    FnDecode decode = (FnDecode)tm_symbol(library, "SherpaOnnxDecodeOnlineStream", error_buffer, error_buffer_size);
    FnGetResult get_result = (FnGetResult)tm_symbol(library, "SherpaOnnxGetOnlineStreamResult", error_buffer, error_buffer_size);
    FnDestroyResult destroy_result = (FnDestroyResult)tm_symbol(library, "SherpaOnnxDestroyOnlineRecognizerResult", error_buffer, error_buffer_size);
    FnInputFinished input_finished = (FnInputFinished)tm_symbol(library, "SherpaOnnxOnlineStreamInputFinished", error_buffer, error_buffer_size);
    FnSetOption set_option = (FnSetOption)tm_symbol(library, "SherpaOnnxOnlineStreamSetOption", error_buffer, error_buffer_size);

    if (!get_version || !create_recognizer || !destroy_recognizer || !create_stream || !destroy_stream ||
        !accept_waveform || !is_ready || !decode || !get_result || !destroy_result || !input_finished || !set_option) {
        dlclose(library);
        return NULL;
    }

    SherpaOnnxOnlineRecognizerConfig config;
    memset(&config, 0, sizeof(config));
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.paraformer.encoder = encoder_path;
    config.model_config.paraformer.decoder = decoder_path;
    config.model_config.tokens = tokens_path;
    config.model_config.provider = "cpu";
    config.model_config.num_threads = num_threads > 0 ? num_threads : 1;
    config.model_config.debug = 0;
    config.decoding_method = "greedy_search";
    config.max_active_paths = 4;
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 2.4f;
    config.rule2_min_trailing_silence = 1.2f;
    config.rule3_min_utterance_length = 20.0f;
    config.hotwords_file = hotwords_path != NULL ? hotwords_path : "";
    config.hotwords_score = 1.5f;

    const SherpaOnnxOnlineRecognizer *recognizer = create_recognizer(&config);
    if (recognizer == NULL) {
        tm_set_error(error_buffer, error_buffer_size, "sherpa-onnx 创建 Paraformer recognizer 失败。");
        dlclose(library);
        return NULL;
    }

    const SherpaOnnxOnlineStream *stream = create_stream(recognizer);
    if (stream == NULL) {
        destroy_recognizer(recognizer);
        dlclose(library);
        tm_set_error(error_buffer, error_buffer_size, "sherpa-onnx 创建 streaming session 失败。");
        return NULL;
    }

    TypeMoreSherpaSession *session = (TypeMoreSherpaSession *)calloc(1, sizeof(TypeMoreSherpaSession));
    session->library_handle = library;
    session->recognizer = recognizer;
    session->stream = stream;
    session->get_version = get_version;
    session->destroy_recognizer = destroy_recognizer;
    session->destroy_stream = destroy_stream;
    session->accept_waveform = accept_waveform;
    session->is_ready = is_ready;
    session->decode = decode;
    session->get_result = get_result;
    session->destroy_result = destroy_result;
    session->input_finished = input_finished;
    session->set_option = set_option;
    return session;
}

void tm_sherpa_accept_waveform(
    TypeMoreSherpaSession *session,
    int32_t sample_rate,
    const float *samples,
    int32_t sample_count) {
    if (session == NULL || samples == NULL || sample_count <= 0) {
        return;
    }
    session->accept_waveform(session->stream, sample_rate, samples, sample_count);
    tm_decode_ready(session);
}

void tm_sherpa_finish(TypeMoreSherpaSession *session) {
    if (session == NULL) {
        return;
    }
    if (session->set_option) {
        session->set_option(session->stream, "is_final", "1");
    }
    session->input_finished(session->stream);
    tm_decode_ready(session);
}

int32_t tm_sherpa_copy_result(
    TypeMoreSherpaSession *session,
    char *text_buffer,
    int32_t text_buffer_size) {
    if (text_buffer == NULL || text_buffer_size <= 0) {
        return 0;
    }
    text_buffer[0] = '\0';
    if (session == NULL) {
        return 0;
    }

    const SherpaOnnxOnlineRecognizerResult *result = session->get_result(session->recognizer, session->stream);
    if (result == NULL || result->text == NULL) {
        if (result != NULL) {
            session->destroy_result(result);
        }
        return 0;
    }

    snprintf(text_buffer, (size_t)text_buffer_size, "%s", result->text);
    int32_t length = (int32_t)strlen(text_buffer);
    session->destroy_result(result);
    return length;
}

const char *tm_sherpa_version(TypeMoreSherpaSession *session) {
    if (session == NULL || session->get_version == NULL) {
        return "";
    }
    return session->get_version();
}

void tm_sherpa_destroy(TypeMoreSherpaSession *session) {
    if (session == NULL) {
        return;
    }
    if (session->stream != NULL) {
        session->destroy_stream(session->stream);
    }
    if (session->recognizer != NULL) {
        session->destroy_recognizer(session->recognizer);
    }
    if (session->library_handle != NULL) {
        dlclose(session->library_handle);
    }
    free(session);
}
