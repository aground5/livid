#include "WebMSupportCpp/FFmpegWrapper.hpp"
#include "WebMSupportCpp/FFmpegWrapperC.h"
#include <cstdio>
#include <iostream>
#include <string>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libswscale/swscale.h>
}

// Global initialization (only once)
static void init_ffmpeg() {
  static bool initialized = false;
  if (!initialized) {
    initialized = true;
  }
}

static int init_filter_graph(AVFilterGraph **graph, AVFilterContext **src,
                             AVFilterContext **sink, const char *filters_descr,
                             AVCodecContext *dec_ctx, AVCodecContext *enc_ctx) {
  char args[512];
  int ret = 0;
  AVFilterGraph *filter_graph = avfilter_graph_alloc();

  if (!filter_graph) {
    ret = AVERROR(ENOMEM);
    return ret;
  }

  snprintf(args, sizeof(args),
           "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/"
           "%d:color_range=%d:colorspace=%d:color_primaries=%d:color_trc=%d",
           dec_ctx->width, dec_ctx->height, dec_ctx->pix_fmt,
           dec_ctx->time_base.num, dec_ctx->time_base.den,
           dec_ctx->sample_aspect_ratio.num, dec_ctx->sample_aspect_ratio.den,
           dec_ctx->color_range, dec_ctx->colorspace, dec_ctx->color_primaries,
           dec_ctx->color_trc);

  // Build complete filter string: buffer -> user filters -> buffersink
  std::string full_descr = std::string("buffer=") + args + "[in];[in]" +
                           filters_descr + "[out];[out]buffersink";

  AVFilterInOut *inputs = nullptr;
  AVFilterInOut *outputs = nullptr;

  ret = avfilter_graph_parse2(filter_graph, full_descr.c_str(), &inputs,
                              &outputs);
  if (ret < 0) {
    avfilter_graph_free(&filter_graph);
    return ret;
  }

  // Free the inputs/outputs as we don't need them
  avfilter_inout_free(&inputs);
  avfilter_inout_free(&outputs);

  // Find the buffer and buffersink filters
  *src = avfilter_graph_get_filter(filter_graph, "Parsed_buffer_0");
  *sink = avfilter_graph_get_filter(filter_graph, "Parsed_buffersink_");

  // Try alternative names if not found
  if (!*sink) {
    for (unsigned i = 0; i < filter_graph->nb_filters; i++) {
      if (strcmp(filter_graph->filters[i]->filter->name, "buffersink") == 0) {
        *sink = filter_graph->filters[i];
        break;
      }
    }
  }
  if (!*src) {
    for (unsigned i = 0; i < filter_graph->nb_filters; i++) {
      if (strcmp(filter_graph->filters[i]->filter->name, "buffer") == 0) {
        *src = filter_graph->filters[i];
        break;
      }
    }
  }

  if (!*src || !*sink) {
    avfilter_graph_free(&filter_graph);
    return AVERROR(EINVAL);
  }

  // Configure the filter graph
  ret = avfilter_graph_config(filter_graph, nullptr);
  if (ret < 0) {
    avfilter_graph_free(&filter_graph);
    return ret;
  }

  *graph = filter_graph;
  return 0;
}

FFmpegWrapper::FFmpegWrapper(const char *path)
    : m_fmt_ctx(nullptr), m_dec_ctx(nullptr), m_frame(nullptr), m_pkt(nullptr),
      m_video_stream_idx(-1), m_decoder_initialized(false) {

  init_ffmpeg();

  if (avformat_open_input(&m_fmt_ctx, path, nullptr, nullptr) < 0) {
    return;
  }

  if (avformat_find_stream_info(m_fmt_ctx, nullptr) < 0) {
    return;
  }

  for (unsigned int i = 0; i < m_fmt_ctx->nb_streams; i++) {
    if (m_fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
      m_video_stream_idx = (int)i;
      break;
    }
  }

  m_frame = av_frame_alloc();
  m_pkt = av_packet_alloc();
}

FFmpegWrapper::~FFmpegWrapper() { cleanup(); }

void FFmpegWrapper::cleanup() {
  if (m_dec_ctx) {
    avcodec_free_context(&m_dec_ctx);
    m_dec_ctx = nullptr;
  }
  if (m_fmt_ctx) {
    avformat_close_input(&m_fmt_ctx);
    m_fmt_ctx = nullptr;
  }
  if (m_frame) {
    av_frame_free(&m_frame);
    m_frame = nullptr;
  }
  if (m_pkt) {
    av_packet_free(&m_pkt);
    m_pkt = nullptr;
  }
}

FFmpegWrapper *FFmpegWrapper::create(const char *path) {
  return new FFmpegWrapper(path);
}

void FFmpegWrapper::destroy(FFmpegWrapper *wrapper) { delete wrapper; }

bool FFmpegWrapper::isOpen() const {
  return m_fmt_ctx != nullptr && m_video_stream_idx != -1;
}

double FFmpegWrapper::getDuration() const {
  if (!m_fmt_ctx)
    return 0;
  return (double)m_fmt_ctx->duration / AV_TIME_BASE;
}

int FFmpegWrapper::getWidth() const {
  if (!isOpen())
    return 0;
  return m_fmt_ctx->streams[m_video_stream_idx]->codecpar->width;
}

int FFmpegWrapper::getHeight() const {
  if (!isOpen())
    return 0;
  return m_fmt_ctx->streams[m_video_stream_idx]->codecpar->height;
}

const char *FFmpegWrapper::getCodecName() const {
  if (!isOpen())
    return "unknown";
  const AVCodecDescriptor *desc = avcodec_descriptor_get(
      m_fmt_ctx->streams[m_video_stream_idx]->codecpar->codec_id);
  return desc ? desc->name : "unknown";
}

bool FFmpegWrapper::initDecoder() {
  if (m_decoder_initialized)
    return true;
  if (!isOpen())
    return false;

  AVCodecParameters *params = m_fmt_ctx->streams[m_video_stream_idx]->codecpar;
  const AVCodec *codec = nullptr;

  // Try to find a hardware decoder for VP9 if possible (for quick mode)
  if (params->codec_id == AV_CODEC_ID_VP9) {
    codec = avcodec_find_decoder_by_name("vp9_videotoolbox");
  }

  if (!codec) {
    codec = avcodec_find_decoder(params->codec_id);
  }

  // For AV1, explicitly avoid hardware decoders that might be problematic on
  // unsupported hardware
  if (params->codec_id == AV_CODEC_ID_AV1) {
    if (codec &&
        (std::string(codec->name).find("videotoolbox") != std::string::npos)) {
      // Try precise software decoders first
      const AVCodec *sw = avcodec_find_decoder_by_name("libdav1d");
      if (!sw)
        sw = avcodec_find_decoder_by_name("av1");

      if (sw) {
        codec = sw;
      }
    }
  }

  if (!codec)
    return false;

  printf("[FFmpegWrapper] Using decoder: %s\n", codec->name);

  m_dec_ctx = avcodec_alloc_context3(codec);
  if (avcodec_parameters_to_context(m_dec_ctx, params) < 0)
    return false;

  // Essential for filter graph and some encoders
  m_dec_ctx->time_base = m_fmt_ctx->streams[m_video_stream_idx]->time_base;
  m_dec_ctx->framerate = av_guess_frame_rate(
      m_fmt_ctx, m_fmt_ctx->streams[m_video_stream_idx], nullptr);

  // Multi-threading
  m_dec_ctx->thread_count = 0;
  m_dec_ctx->thread_type = FF_THREAD_FRAME;

  if (avcodec_open2(m_dec_ctx, codec, nullptr) < 0)
    return false;

  m_decoder_initialized = true;
  return true;
}

VideoFrameInfo FFmpegWrapper::decodeNextFrame() {
  VideoFrameInfo info = {0};
  if (!initDecoder())
    return info;

  while (av_read_frame(m_fmt_ctx, m_pkt) >= 0) {
    if (m_pkt->stream_index == m_video_stream_idx) {
      int ret = avcodec_send_packet(m_dec_ctx, m_pkt);
      av_packet_unref(m_pkt);
      if (ret < 0)
        continue;

      ret = avcodec_receive_frame(m_dec_ctx, m_frame);
      if (ret == 0) {
        info.width = m_frame->width;
        info.height = m_frame->height;
        for (int i = 0; i < 3; i++) {
          info.planes[i] = m_frame->data[i];
          info.strides[i] = m_frame->linesize[i];
        }
        info.timestamp_ns = av_rescale_q(
            m_frame->pts, m_fmt_ctx->streams[m_video_stream_idx]->time_base,
            {1, 1000000000});
        info.is_key = (m_frame->flags & AV_FRAME_FLAG_KEY);
        return info;
      }
    } else {
      av_packet_unref(m_pkt);
    }
  }
  return info;
}

bool FFmpegWrapper::prepareToMov(const char *outputPath, double startTime,
                                 double endTime, ProgressCallback cb,
                                 void *user_data) {
  TranscodeSettings settings;
  settings.encoderName = "hevc_videotoolbox";
  settings.targetHeight = 0; // Use original resolution
  settings.targetFps = 0;    // Use original frame rate
  settings.bitrate = 10000000;
  settings.profile = AV_PROFILE_HEVC_MAIN;
  settings.swsFlags = SWS_POINT;
  settings.x265Params = nullptr;
  settings.preset = nullptr;
  settings.crf = nullptr;
  settings.timescale = 0; // Let FFmpeg decide (Auto)
  settings.realtime = true;
  settings.tonemap = false;
  settings.tenBit = false;
  settings.startTime = startTime;
  settings.endTime = endTime;
  settings.useFilterGraph =
      false; // Never use filters in prepare mode (keep it fast)
  return transcodeInternal(outputPath, settings, cb, user_data);
}

bool FFmpegWrapper::exportToMov(const char *outputPath, double startTime,
                                double endTime, ProgressCallback cb,
                                void *user_data) {
  TranscodeSettings settings;
  settings.encoderName = "libx265";
  settings.targetHeight = 0; // Original
  settings.targetFps = 0;    // Original
  settings.bitrate = 0;      // Auto
  settings.profile = -1;
  settings.swsFlags = SWS_BICUBIC;
  settings.x265Params =
      "bframes=4:b-adapt=2:b-pyramid=1:keyint=240:min-keyint=240:no-scenecut=1:"
      "open-gop=0:temporal-layers=3";
  settings.preset = "medium";
  settings.crf = "22";
  settings.timescale = 240000;
  settings.realtime = false;
  settings.tonemap =
      false; // Default to false, detected in transcodeInternal or set via Ext
  settings.tenBit = true; // Default export to 10-bit for quality
  settings.startTime = startTime;
  settings.endTime = endTime;
  settings.useFilterGraph =
      true; // Use filters (including HDR tone mapping) for export
  return transcodeInternal(outputPath, settings, cb, user_data);
}

bool FFmpegWrapper::exportToMovExt(const char *outputPath, double startTime,
                                   double endTime, bool tonemap, bool tenBit,
                                   ProgressCallback cb, void *user_data) {
  TranscodeSettings settings;
  settings.encoderName = "libx265";
  settings.targetHeight = 0;
  settings.targetFps = 0;
  settings.bitrate = 0;
  settings.profile = -1;
  settings.swsFlags = SWS_BICUBIC;
  settings.x265Params =
      "bframes=4:b-adapt=2:b-pyramid=1:keyint=240:min-keyint=240:no-scenecut=1:"
      "open-gop=0:temporal-layers=3";
  settings.preset = "medium";
  settings.crf = "22";
  settings.timescale = 240000;
  settings.realtime = false;
  settings.tonemap = tonemap;
  settings.tenBit = tenBit;
  settings.startTime = startTime;
  settings.endTime = endTime;
  settings.useFilterGraph = true;
  return transcodeInternal(outputPath, settings, cb, user_data);
}

bool FFmpegWrapper::transcodeInternal(const char *outputPath,
                                      const TranscodeSettings &settings,
                                      ProgressCallback progressCallback,
                                      void *user_data) {
  if (!isOpen())
    return false;

  AVFormatContext *out_fmt_ctx = nullptr;
  if (avformat_alloc_output_context2(&out_fmt_ctx, nullptr, "mov", outputPath) <
      0)
    return false;

  if (!initDecoder()) {
    avformat_free_context(out_fmt_ctx);
    return false;
  }

  const AVCodec *enc = nullptr;
  if (settings.encoderName) {
    enc = avcodec_find_encoder_by_name(settings.encoderName);
  }

  if (!enc) {
    enc = avcodec_find_encoder(AV_CODEC_ID_HEVC);
  }

  if (!enc) {
    avformat_free_context(out_fmt_ctx);
    return false;
  }

  AVCodecContext *enc_ctx = avcodec_alloc_context3(enc);

  if (settings.targetHeight > 0 && m_dec_ctx->height > settings.targetHeight) {
    double scale = (double)settings.targetHeight / m_dec_ctx->height;
    enc_ctx->width = ((int)(m_dec_ctx->width * scale)) & ~1;
    enc_ctx->height = settings.targetHeight;
  } else {
    enc_ctx->width = m_dec_ctx->width;
    enc_ctx->height = m_dec_ctx->height;
  }

  enc_ctx->sample_aspect_ratio = m_dec_ctx->sample_aspect_ratio;

  if (std::string(enc->name).find("videotoolbox") != std::string::npos) {
    enc_ctx->pix_fmt = AV_PIX_FMT_NV12;
    if (settings.profile >= 0) {
      enc_ctx->profile = settings.profile;
    }
  } else {
    if (settings.tenBit || m_dec_ctx->pix_fmt == AV_PIX_FMT_YUV420P10LE ||
        m_dec_ctx->color_trc == AVCOL_TRC_SMPTE2084 ||
        m_dec_ctx->color_trc == AVCOL_TRC_ARIB_STD_B67) {
      enc_ctx->pix_fmt = AV_PIX_FMT_YUV420P10LE;
      enc_ctx->profile = AV_PROFILE_HEVC_MAIN_10;
    } else {
      enc_ctx->pix_fmt = AV_PIX_FMT_YUV420P;
    }
  }

  // Force SDR BT.709 tags for 10-bit SDR output
  enc_ctx->color_range = AVCOL_RANGE_MPEG;
  enc_ctx->color_primaries = AVCOL_PRI_BT709;
  enc_ctx->color_trc = AVCOL_TRC_BT709;
  enc_ctx->colorspace = AVCOL_SPC_BT709;

  AVRational input_frame_rate = av_guess_frame_rate(
      m_fmt_ctx, m_fmt_ctx->streams[m_video_stream_idx], nullptr);
  if (input_frame_rate.num == 0)
    input_frame_rate = {60, 1};

  AVRational target_frame_rate = input_frame_rate;
  if (settings.targetFps > 0 &&
      av_q2d(input_frame_rate) > (double)settings.targetFps) {
    target_frame_rate = {settings.targetFps, 1};
  }
  enc_ctx->time_base = av_inv_q(target_frame_rate);

  if (std::string(enc->name) == "libx265") {
    if (settings.x265Params)
      av_opt_set(enc_ctx->priv_data, "x265-params", settings.x265Params, 0);
    if (settings.preset)
      av_opt_set(enc_ctx->priv_data, "preset", settings.preset, 0);
    if (settings.crf)
      av_opt_set(enc_ctx->priv_data, "crf", settings.crf, 0);
  } else if (std::string(enc->name).find("videotoolbox") != std::string::npos) {
    if (settings.bitrate > 0)
      enc_ctx->bit_rate = settings.bitrate;
    // Keep internal profile if not overwritten
    if (settings.profile >= 0) {
      enc_ctx->profile = settings.profile;
    }
  }

  if (out_fmt_ctx->oformat->flags & AVFMT_GLOBALHEADER) {
    enc_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
  }

  if (avcodec_open2(enc_ctx, enc, nullptr) < 0) {
    avcodec_free_context(&enc_ctx);
    avformat_free_context(out_fmt_ctx);
    return false;
  }

  AVStream *out_stream = avformat_new_stream(out_fmt_ctx, nullptr);
  avcodec_parameters_from_context(out_stream->codecpar, enc_ctx);
  out_stream->codecpar->codec_tag = MKTAG('h', 'v', 'c', '1');

  if (settings.timescale > 0) {
    out_stream->time_base = {1, settings.timescale};
  }

  if (!(out_fmt_ctx->oformat->flags & AVFMT_NOFILE)) {
    if (avio_open(&out_fmt_ctx->pb, outputPath, AVIO_FLAG_WRITE) < 0) {
      avcodec_free_context(&enc_ctx);
      avformat_free_context(out_fmt_ctx);
      return false;
    }
  }

  if (avformat_write_header(out_fmt_ctx, nullptr) < 0) {
    avcodec_free_context(&enc_ctx);
    avformat_free_context(out_fmt_ctx);
    return false;
  }

  // --- SEEK LOGIC ---
  if (settings.startTime > 0) {
    int64_t seek_target = (int64_t)(settings.startTime * AV_TIME_BASE);
    av_seek_frame(m_fmt_ctx, -1, seek_target, AVSEEK_FLAG_BACKWARD);
    // Flush decoder after seek
    avcodec_flush_buffers(m_dec_ctx);
  }
  // ------------------

  AVPacket *in_pkt = av_packet_alloc();
  AVPacket *out_pkt = av_packet_alloc();
  AVFrame *dec_frame = av_frame_alloc();
  AVFrame *enc_frame = av_frame_alloc();
  enc_frame->format = enc_ctx->pix_fmt;
  enc_frame->width = enc_ctx->width;
  enc_frame->height = enc_ctx->height;
  av_frame_get_buffer(enc_frame, 0);

  AVFilterGraph *filter_graph = nullptr;
  AVFilterContext *filt_src = nullptr;
  AVFilterContext *filt_sink = nullptr;
  struct SwsContext *sws_ctx = nullptr;

  AVFrame *filt_frame = av_frame_alloc();    // For filter output
  AVFrame *sws_out_frame = av_frame_alloc(); // For manual sws output

  // Calculate effective duration for progress
  double asset_duration_sec = (double)m_fmt_ctx->duration / AV_TIME_BASE;
  double effective_end =
      (settings.endTime > 0 && settings.endTime < asset_duration_sec)
          ? settings.endTime
          : asset_duration_sec;
  double duration_sec = effective_end - settings.startTime;
  if (duration_sec < 0)
    duration_sec = 0;

  int64_t pts_counter = 0;
  int64_t frame_idx = 0;
  bool stop_encoding = false;

  // Decide on filters
  std::string filter_descr = "null";
  bool is_hdr = (m_dec_ctx->color_trc == AVCOL_TRC_SMPTE2084 ||
                 m_dec_ctx->color_trc == AVCOL_TRC_ARIB_STD_B67);

  if (settings.useFilterGraph) {
    if (is_hdr || settings.tonemap) {
      // HDR to SDR Tone Mapping with proper color space conversion
      // 1. Convert to linear light (required for tonemap)
      // 2. Apply tone mapping (hable is good for generic use)
      // 3. Convert to BT.709 SDR
      // 4. Convert pixel format if needed
      filter_descr = "zscale=transfer=linear:npl=100,tonemap=hable,zscale="
                     "transfer=bt709:primaries=bt709:matrix=bt709,format=" +
                     std::string(av_get_pix_fmt_name(enc_ctx->pix_fmt));
      printf("[FFmpegWrapper] Tone mapping enabled. Filter: %s\n",
             filter_descr.c_str());
    } else if (m_dec_ctx->width != enc_ctx->width ||
               m_dec_ctx->height != enc_ctx->height ||
               m_dec_ctx->pix_fmt != enc_ctx->pix_fmt) {
      // Optimized SDR path: Use zscale for high-quality scaling and bit-depth
      // expansion. This avoids the 'bgr48le' accelerated path warning by
      // staying in the YUV domain.
      std::string scale_part = "";
      if (m_dec_ctx->width != enc_ctx->width ||
          m_dec_ctx->height != enc_ctx->height) {
        scale_part = "zscale=w=" + std::to_string(enc_ctx->width) +
                     ":h=" + std::to_string(enc_ctx->height) + ":f=spline36,";
      }

      // 8->10 bit upconversion with error diffusion dither to prevent banding.
      // We explicitly set the matrix and primaries to BT.709 for standard SDR.
      filter_descr =
          scale_part +
          "zscale=p=bt709:t=bt709:m=bt709:range=limited:d=error_diffusion,"
          "format=" +
          std::string(av_get_pix_fmt_name(enc_ctx->pix_fmt));
      printf("[FFmpegWrapper] Optimized SDR 8->10 bit path. Filter: %s\n",
             filter_descr.c_str());
    }
  }

  if (filter_descr != "null") {
    if (init_filter_graph(&filter_graph, &filt_src, &filt_sink,
                          filter_descr.c_str(), m_dec_ctx, enc_ctx) < 0) {
      printf("[FFmpegWrapper] Error: Failed to initialize filter graph\n");
      // Fallback to null or fail
    }
  }

  while (av_read_frame(m_fmt_ctx, in_pkt) >= 0) {
    if (in_pkt->stream_index == m_video_stream_idx) {
      if (avcodec_send_packet(m_dec_ctx, in_pkt) == 0) {
        while (avcodec_receive_frame(m_dec_ctx, dec_frame) == 0) {

          // Get current frame timestamp in seconds
          double current_time =
              dec_frame->pts *
              av_q2d(m_fmt_ctx->streams[m_video_stream_idx]->time_base);

          // Trimming Logic
          if (current_time < settings.startTime)
            continue;
          if (settings.endTime > 0 && current_time > settings.endTime) {
            stop_encoding = true;
            break;
          }

          // Frame rate control/skipping
          if (settings.targetFps > 0 &&
              av_q2d(input_frame_rate) > (double)settings.targetFps) {
            double ratio =
                av_q2d(input_frame_rate) / (double)settings.targetFps;
            if (frame_idx++ % (int)ratio != 0)
              continue;
          } else {
            frame_idx++;
          }

          // --- PROCESSING & ENCODING ---
          // Filter Graph 경로
          if (filter_graph) {
            if (av_buffersrc_add_frame_flags(filt_src, dec_frame,
                                             AV_BUFFERSRC_FLAG_KEEP_REF) >= 0) {
              while (true) {
                av_frame_unref(filt_frame);
                int ret = av_buffersink_get_frame(filt_sink, filt_frame);
                if (ret < 0)
                  break;

                filt_frame->pts = pts_counter++;
                filt_frame->pict_type = AV_PICTURE_TYPE_NONE; // ← 추가!

                if (avcodec_send_frame(enc_ctx, filt_frame) == 0) {
                  while (avcodec_receive_packet(enc_ctx, out_pkt) == 0) {
                    av_packet_rescale_ts(out_pkt, enc_ctx->time_base,
                                         out_stream->time_base);
                    out_pkt->stream_index = out_stream->index;
                    av_interleaved_write_frame(out_fmt_ctx, out_pkt);
                    av_packet_unref(out_pkt);
                  }
                }
              }
            }
          } // Legacy Path (Manual Scaling)
          else {
            if (!sws_ctx) {
              sws_ctx = sws_getContext(dec_frame->width, dec_frame->height,
                                       (AVPixelFormat)dec_frame->format,
                                       enc_ctx->width, enc_ctx->height,
                                       enc_ctx->pix_fmt, settings.swsFlags,
                                       nullptr, nullptr, nullptr);

              sws_out_frame->format = enc_ctx->pix_fmt;
              sws_out_frame->width = enc_ctx->width;
              sws_out_frame->height = enc_ctx->height;
              av_frame_get_buffer(sws_out_frame, 0);
            }

            if (sws_ctx) {
              sws_scale(sws_ctx, dec_frame->data, dec_frame->linesize, 0,
                        dec_frame->height, sws_out_frame->data,
                        sws_out_frame->linesize);
              sws_out_frame->pts = pts_counter++;
              sws_out_frame->pict_type = AV_PICTURE_TYPE_NONE; // ← 추가!

              if (avcodec_send_frame(enc_ctx, sws_out_frame) == 0) {
                while (avcodec_receive_packet(enc_ctx, out_pkt) == 0) {
                  av_packet_rescale_ts(out_pkt, enc_ctx->time_base,
                                       out_stream->time_base);
                  out_pkt->stream_index = out_stream->index;
                  av_interleaved_write_frame(out_fmt_ctx, out_pkt);
                  av_packet_unref(out_pkt);
                }
              }
            }
          }

          if (progressCallback && duration_sec > 0) {
            double progress =
                (current_time - settings.startTime) / duration_sec;
            if (progress < 0)
              progress = 0;
            if (progress > 1.0)
              progress = 1.0;
            progressCallback(progress, user_data);
          }
        }
      }
    }
    av_packet_unref(in_pkt);
    if (stop_encoding)
      break;
  }

  // --- FINAL FLUSHING ---
  if (filter_graph) {
    av_buffersrc_add_frame_flags(filt_src, nullptr, 0);
    while (av_buffersink_get_frame(filt_sink, filt_frame) >= 0) {
      filt_frame->pts = pts_counter++;
      filt_frame->pict_type = AV_PICTURE_TYPE_NONE; // ← 추가!

      if (avcodec_send_frame(enc_ctx, filt_frame) == 0) {
        while (avcodec_receive_packet(enc_ctx, out_pkt) == 0) {
          av_packet_rescale_ts(out_pkt, enc_ctx->time_base,
                               out_stream->time_base);
          out_pkt->stream_index = out_stream->index;
          av_interleaved_write_frame(out_fmt_ctx, out_pkt);
          av_packet_unref(out_pkt);
        }
      }
      av_frame_unref(filt_frame);
    }
  }
  avcodec_send_frame(enc_ctx, nullptr);
  while (avcodec_receive_packet(enc_ctx, out_pkt) == 0) {
    av_packet_rescale_ts(out_pkt, enc_ctx->time_base, out_stream->time_base);
    out_pkt->stream_index = out_stream->index;
    av_interleaved_write_frame(out_fmt_ctx, out_pkt);
    av_packet_unref(out_pkt);
  }

  av_write_trailer(out_fmt_ctx);

  if (filter_graph)
    avfilter_graph_free(&filter_graph);
  if (sws_ctx)
    sws_freeContext(sws_ctx);

  av_frame_free(&filt_frame);
  av_frame_free(&sws_out_frame);
  av_frame_free(&dec_frame);
  av_frame_free(&enc_frame);
  av_packet_free(&in_pkt);
  av_packet_free(&out_pkt);
  avcodec_free_context(&enc_ctx);
  if (!(out_fmt_ctx->oformat->flags & AVFMT_NOFILE)) {
    avio_closep(&out_fmt_ctx->pb);
  }
  avformat_free_context(out_fmt_ctx);

  return true;
}

// C Bridge Implementations
extern "C" {
FFmpegWrapperRef FFmpegWrapper_Create(const char *path) {
  return (FFmpegWrapperRef) new FFmpegWrapper(path);
}
void FFmpegWrapper_Destroy(FFmpegWrapperRef ref) {
  delete (FFmpegWrapper *)ref;
}
bool FFmpegWrapper_IsOpen(FFmpegWrapperRef ref) {
  if (!ref)
    return false;
  return ((FFmpegWrapper *)ref)->isOpen();
}
double FFmpegWrapper_GetDuration(FFmpegWrapperRef ref) {
  if (!ref)
    return 0;
  return ((FFmpegWrapper *)ref)->getDuration();
}
int FFmpegWrapper_GetWidth(FFmpegWrapperRef ref) {
  if (!ref)
    return 0;
  return ((FFmpegWrapper *)ref)->getWidth();
}
int FFmpegWrapper_GetHeight(FFmpegWrapperRef ref) {
  if (!ref)
    return 0;
  return ((FFmpegWrapper *)ref)->getHeight();
}
const char *FFmpegWrapper_GetCodecName(FFmpegWrapperRef ref) {
  if (!ref)
    return "unknown";
  return ((FFmpegWrapper *)ref)->getCodecName();
}
bool FFmpegWrapper_PrepareToMov(FFmpegWrapperRef ref, const char *outputPath,
                                double startTime, double endTime,
                                FFmpegProgressCallback cb, void *user_data) {
  if (!ref)
    return false;
  return ((FFmpegWrapper *)ref)
      ->prepareToMov(outputPath, startTime, endTime,
                     (FFmpegWrapper::ProgressCallback)cb, user_data);
}

bool FFmpegWrapper_ExportToMov(FFmpegWrapperRef ref, const char *outputPath,
                               double startTime, double endTime,
                               FFmpegProgressCallback cb, void *user_data) {
  if (!ref)
    return false;
  return ((FFmpegWrapper *)ref)
      ->exportToMov(outputPath, startTime, endTime,
                    (FFmpegWrapper::ProgressCallback)cb, user_data);
}

bool FFmpegWrapper_ExportToMovExt(FFmpegWrapperRef ref, const char *outputPath,
                                  double startTime, double endTime,
                                  bool tonemap, bool tenBit,
                                  FFmpegProgressCallback cb, void *user_data) {
  if (!ref)
    return false;
  return ((FFmpegWrapper *)ref)
      ->exportToMovExt(outputPath, startTime, endTime, tonemap, tenBit,
                       (FFmpegWrapper::ProgressCallback)cb, user_data);
}
}