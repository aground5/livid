#ifndef FFMPEG_WRAPPER_C_H
#define FFMPEG_WRAPPER_C_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *FFmpegWrapperRef;

FFmpegWrapperRef FFmpegWrapper_Create(const char *path);
void FFmpegWrapper_Destroy(FFmpegWrapperRef ref);
bool FFmpegWrapper_IsOpen(FFmpegWrapperRef ref);
double FFmpegWrapper_GetDuration(FFmpegWrapperRef ref);
int FFmpegWrapper_GetWidth(FFmpegWrapperRef ref);
int FFmpegWrapper_GetHeight(FFmpegWrapperRef ref);
const char *FFmpegWrapper_GetCodecName(FFmpegWrapperRef ref);

typedef void (*FFmpegProgressCallback)(double progress, void *user_data);
bool FFmpegWrapper_PrepareToMov(FFmpegWrapperRef ref, const char *outputPath,
                                double startTime, double endTime,
                                FFmpegProgressCallback cb, void *user_data);
bool FFmpegWrapper_ExportToMov(FFmpegWrapperRef ref, const char *outputPath,
                               double startTime, double endTime,
                               FFmpegProgressCallback cb, void *user_data);

bool FFmpegWrapper_ExportToMovExt(FFmpegWrapperRef ref, const char *outputPath,
                                  double startTime, double endTime,
                                  bool tonemap, bool tenBit,
                                  FFmpegProgressCallback cb, void *user_data);

#ifdef __cplusplus
}
#endif

#endif // FFMPEG_WRAPPER_C_H
