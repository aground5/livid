#ifndef FFMPEG_WRAPPER_HPP
#define FFMPEG_WRAPPER_HPP

#include <cstdint>
#include <vector>

typedef std::vector<uint8_t> Uint8Vector;

// Forward declarations
struct AVFormatContext;
struct AVCodecContext;
struct AVFrame;
struct AVPacket;

struct VideoFrameInfo {
  const uint8_t *planes[4];
  int strides[4];
  int width;
  int height;
  long long timestamp_ns;
  bool is_key;
};

class FFmpegWrapper {
public:
  FFmpegWrapper(const char *path);
  ~FFmpegWrapper();

  static FFmpegWrapper *create(const char *path);
  static void destroy(FFmpegWrapper *wrapper);

  bool isOpen() const;
  double getDuration() const;
  int getWidth() const;
  int getHeight() const;
  const char *getCodecName() const;

  // Transcoding with specific x265 params for Apple/Live Wallpaper
  // compatibility
  typedef void (*ProgressCallback)(double progress, void *user_data);
  bool prepareToMov(const char *outputPath, double startTime, double endTime,
                    ProgressCallback cb, void *user_data);
  bool exportToMov(const char *outputPath, double startTime, double endTime,
                   ProgressCallback cb, void *user_data);
  bool exportToMovExt(const char *outputPath, double startTime, double endTime,
                      bool tonemap, bool tenBit, ProgressCallback cb,
                      void *user_data);

  // Manual decoding (if needed)
  bool initDecoder();
  VideoFrameInfo decodeNextFrame();

private:
  AVFormatContext *m_fmt_ctx;
  AVCodecContext *m_dec_ctx;
  AVFrame *m_frame;
  AVPacket *m_pkt;
  int m_video_stream_idx;
  bool m_decoder_initialized;

  struct TranscodeSettings {
    const char *encoderName;
    int targetHeight; // 0 for original
    int targetFps;    // 0 for original
    int64_t bitrate;
    int profile;
    int swsFlags;
    const char *x265Params;
    const char *preset;
    const char *crf;
    int timescale; // e.g. 240000
    bool realtime;
    bool tonemap;
    bool tenBit;
    double startTime;
    double endTime;
    bool useFilterGraph;
  };

  bool transcodeInternal(const char *outputPath,
                         const TranscodeSettings &settings,
                         ProgressCallback progressCallback, void *user_data);
  void cleanup();
};

#endif
