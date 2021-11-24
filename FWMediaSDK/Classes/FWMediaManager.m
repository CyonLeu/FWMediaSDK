//
//  FWMediaManager.m
//  FWMediaSDK
//
//  Created by Yong Liu on 2021/11/24.
//

#import "FWMediaManager.h"

#import <ffmpegkit/FFmpegKitConfig.h>
#import <ffmpegkit/FFmpegKit.h>
#import <ffmpegkit/MediaInformation.h>


@interface FWMediaManager ()

@property (assign, nonatomic) long asyncId;
@property (copy, nonatomic) void (^progressTimeBlock)(NSTimeInterval time);
@property (copy, nonatomic) void (^runResultBlock)(BOOL success);

@end


@implementation FWMediaManager

+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    static FWMediaManager *instance;
    dispatch_once(&onceToken, ^{
        instance = [[FWMediaManager alloc] init];
    });
    return instance;
}

#pragma mark -  Audio Handle -

/**
 根据时间段来裁剪音频文件:
 把一段音频裁剪为多段，根据数组时间点，
 并放到toPathDir目录下，文件名以index字段来命名
 timeArray：多个NSDictionary对象
 包含三个值{"index":"1", "beginTime":@(1.3), "endTime":@(3.0)}
 */
- (void)cutAudioFile:(NSString *)filePath toPath:(NSString *)toPathDir timeArray:(NSArray *)timeArray {
    NSString *prePath = toPathDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:prePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:prePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    for (int i = 0; i < timeArray.count; ++i) {
        NSDictionary *dict = timeArray[i];
        NSString *fileName = dict[@"index"];
        if (fileName) {
            fileName = [fileName stringByAppendingPathExtension:[filePath pathExtension]];
            NSString *destPath = [prePath stringByAppendingPathComponent:fileName];
            float beginTime = [[dict objectForKey:@"beginTime"] floatValue];
            float endTime = [[dict objectForKey:@"endTime"] floatValue];
            NSString *command = [NSString stringWithFormat:@"-hide_banner -y -i %@ -ss %f -to %f -acodec copy %@", filePath, beginTime, endTime, destPath];
            dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // EXECUTE
                FFmpegSession *session = [FFmpegKit execute:command];
                ReturnCode *returnCode = [session getReturnCode];
                if ([returnCode isSuccess]) {
                    NSLog(@"Encode completed successfully.\n");
                } else {
                    NSLog(@"Encode failed with rc=%d\n", [returnCode getValue]);
                }
            });
        }
        
    }
}


#pragma mark - Video Handle  -

/**
 根据时间段来裁剪单个媒体文件：裁剪媒体片段，可裁剪音频或视频
 beginTime:开始时间
 endTime:结束时间
 mediaType:FWMediaTypeAudio 或 FWMediaTypeVideo
 */
- (FWMediaState)cutMediaFile:(NSString *)filePath
                      toPath:(NSString *)toPath
                   beginTime:(double)beginTime
                     endTime:(double)endTime
                   mediaType:(FWMediaType)mediaType
                timeProgress:(void (^)(NSTimeInterval time))timeProgress
                 finishBlock:(void (^)(BOOL success))finishBlock {
    
    if (self.asyncId > 0) {
        return FWMediaStatePreviousTaskNotFinish;
    }
    
    if (!toPath) {
        return FWMediaStateErrorPath;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:toPath error:nil];
    }
    
    
    NSString *dirPath = [toPath stringByDeletingLastPathComponent];
    BOOL isDir = NO;
    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDir];
    if (isExist && isDir) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    self.progressTimeBlock = timeProgress;
    self.runResultBlock = finishBlock;
    
    NSString *mediaCode = @"-c:v libx264 -c:a aac";
    if (mediaType == FWMediaTypeAudio) {
        mediaCode = @"-c copy";
    }
    
    NSString *command = [NSString stringWithFormat:@"-ss %f -i %@ -to %f %@ %@", beginTime, filePath, endTime, mediaCode, toPath];
    
    WEAKSELF
    [FFmpegKitConfig enableLogCallback:^(Log *log) {
        [weakSelf logCallback:[log getSessionId] :[log getLevel] :[log getMessage]];
    }];
    FFmpegSession *session = [FFmpegKit executeAsync:command withExecuteCallback:^(id<Session> session) {
        ReturnCode *code = [session getReturnCode];
        if (weakSelf.asyncId == [session getSessionId] && code) {
            weakSelf.runResultBlock([code isSuccess]);
            weakSelf.runResultBlock = nil;
            weakSelf.asyncId = 0;
        }
    }];
    self.asyncId = [session getSessionId];
    
    return FWMediaStateSuccess;
}

/// 压缩视频
/// @param videoPath 视频地址
/// @param toPath 结果地址
/// @param finishBlock succ
- (FWMediaState)compressVideo:(NSString *)videoPath toPath:(NSString *)toPath finishBlock:(void (^)(BOOL success))finishBlock {
    if (!toPath) {
        return FWMediaStateErrorPath;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:toPath error:nil];
    }
    
    
    NSString *dirPath = [toPath stringByDeletingLastPathComponent];
    BOOL isDir = NO;
    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDir];
    if (isExist && isDir) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSString *command = [NSString stringWithFormat:@"-i %@ -vf mpdecimate,setpts=N/FRAME_RATE/TB %@", videoPath, toPath];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // EXECUTE
        FFmpegSession *session = [FFmpegKit execute:command];
        ReturnCode *returnCode = [session getReturnCode];
        if ([returnCode isSuccess]) {
            NSLog(@"Encode completed successfully.\n");
        } else {
            NSLog(@"Encode failed with rc=%d\n", [returnCode getValue]);
        }
        
        if (finishBlock) {
            finishBlock([returnCode isSuccess]);
        }
    });
    
    return FWMediaStateSuccess;
}

/// 从视频中抽取用来识别字幕的音频
/// @param videoPath 视频地址
/// @param path 音频地址
/// @param finishBlock finish
- (FWMediaState)extractSrtAudioFromVideo:(NSString *)videoPath toPath:(NSString *)path finishBlock:(void (^)(BOOL success))finishBlock {
    if (!path) {
        return FWMediaStateErrorPath;
    }
    
    if (self.asyncId > 0) {
        return FWMediaStatePreviousTaskNotFinish;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    
    
    NSString *dirPath = [path stringByDeletingLastPathComponent];
    BOOL isDir = NO;
    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDir];
    if (isExist && isDir) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    self.runResultBlock = finishBlock;
    
    NSString *command = [NSString stringWithFormat:@"-i %@ -f wav -ar 16000 -ac 1 %@", videoPath, path];
    WEAKSELF
    FFmpegSession *session = [FFmpegKit executeAsync:command withExecuteCallback:^(id<Session> session) {
        ReturnCode *code = [session getReturnCode];
        if (weakSelf.asyncId == [session getSessionId] && code) {
            weakSelf.runResultBlock([code isSuccess]);
            weakSelf.runResultBlock = nil;
            weakSelf.asyncId = 0;
        }
    }];
    self.asyncId = [session getSessionId];
    return FWMediaStateSuccess;
}

/// 合成音频
/// @param paths 资源文件
/// @param outputPath 输出地址
- (int)compositionMediaWithPaths:(NSArray *)paths times:(NSArray *)times outputPath:(NSString *)outputPath {
    if (paths.count < 2) {
        return 1;
    }
    NSMutableString *inputString = [NSMutableString string];
    NSMutableString *adelayString = [NSMutableString string];
    NSMutableString *compositionString = [NSMutableString stringWithFormat:@"[0]"];
    for (int i = 0; i < paths.count; i++) {
        NSString *path = paths[i];
        NSInteger time = @([times[i] floatValue] * 1000).integerValue;
        [inputString appendFormat:@"-i %@ ", path];
        if (i > 0) {
            [adelayString appendFormat:@"[%d]adelay=%ld|%ld[s%d];", i, (long)time, (long)time, i];
            [compositionString appendFormat:@"[s%d]", i];
        }
    }
    
    [compositionString appendFormat:@"amix=inputs=%lu[o]", (unsigned long)paths.count];
    
    NSString *command = [NSString stringWithFormat:@"%@ -filter_complex \"%@%@\" -map \"[o]\" -f caf %@", inputString, adelayString, compositionString, outputPath];
    FFmpegSession *session = [FFmpegKit execute:command];
    ReturnCode *returnCode = [session getReturnCode];
    return [returnCode getValue];
}

/// 音频文件转aac
/// @param audioPath 音频文件地址
/// @param cafPath 目标文件地址
- (FWMediaState)convertAudio:(NSString *)audioPath toCafPath:(NSString *)cafPath {
    NSString *command = [NSString stringWithFormat:@"-i %@ %@", audioPath, cafPath];
    WEAKSELF
    [FFmpegKitConfig enableLogCallback:^(Log *log) {
        [weakSelf logCallback:[log getSessionId] :[log getLevel] :[log getMessage]];
    }];
    
    FFmpegSession *session = [FFmpegKit execute:command];
    ReturnCode *returnCode = [session getReturnCode];
    if ([returnCode isSuccess]) {
        return FWMediaStateSuccess;
    } else {
        return FWMediaStateError;
    }
}

#pragma mark - 音频信息：根据音频地址获取相关信息 -

- (CGFloat)getMediaDecibelWithFilePath:(NSString *)filePath {
    NSString *command = [NSString stringWithFormat:@"-i %@ -filter_complex volumedetect -c:v copy -f null /dev/null", filePath];
    FFmpegSession *session = [FFmpegKit execute:command];
    ReturnCode *returnCode = [session getReturnCode];
    if (![returnCode isSuccess]) {
        return 0;
    }
    
    id<Session> lastSession = [FFmpegKitConfig getLastCompletedSession];
    NSString *outputString = [lastSession getCommand];
    NSArray *subArray = [outputString componentsSeparatedByString:@"max_volume:"];
    if (subArray.count <= 1) {
        return 0;
    }
    NSString *lastString = subArray.lastObject;
    NSArray *dbArray = [lastString componentsSeparatedByString:@"dB"];
    NSString *maxDB = [dbArray.firstObject stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (maxDB) {
        return [maxDB floatValue];
    }
    return 0;
}

/// 获取音频分贝中位数
/// @param filePath 音频地址
- (CGFloat)getMediaDecibelMedianWithFilePath:(NSString *)filePath {
    NSString *command = [NSString stringWithFormat:@"-i %@ -filter_complex volumedetect -c:v copy -f null /dev/null", filePath];
    FFmpegSession *session = [FFmpegKit execute:command];
    ReturnCode *returnCode = [session getReturnCode];
    if (![returnCode isSuccess]) {
        return 0;
    }
    
    id<Session> lastSession = [FFmpegKitConfig getLastCompletedSession];
    NSString *outputString = [lastSession getCommand];
    
    NSArray *subArray = [outputString componentsSeparatedByString:@"histogram_"];
    if (subArray.count <= 1) {
        return 0;
    }
    NSString *lastString = subArray.lastObject;
    NSArray *dbArray = [lastString componentsSeparatedByString:@"db"];
    NSString *maxDB = dbArray.firstObject;
    if (maxDB) {
        return [maxDB floatValue] * -1.f;
    }
    return 0;
}

- (int)changeMediaDecibelWithInputFilePath:(NSString *)inputPath outputPath:(NSString *)outputPath decibel:(CGFloat)decibel {
    NSString *command = [NSString stringWithFormat:@"-i %@ -af volume=%.1fdB %@", inputPath, decibel, outputPath];
    FFmpegSession *session = [FFmpegKit execute:command];
    ReturnCode *returnCode = [session getReturnCode];
    return [returnCode getValue];
    
}

- (NSDictionary *)getMediaInfoWithPath:(NSString *)path {
    MediaInformationSession *session = [FFprobeKit getMediaInformation:path];
    MediaInformation *info = [session getMediaInformation];
//    NSString *fm = [info getFormat];
//    NSString *lfm = [info getLongFormat];
//    NSDictionary *mD = [info getMediaProperties];
    NSDictionary *dic = [info getAllProperties];
    return dic;
}

#pragma mark - 获取图片帧 或 添加水印

/// 视频截图
/// @param videoPath 视频地址
/// @param startTime 截图起始时间
/// @param fps 每秒多少张
/// @param picDirectory 图片保存目录
/// @param picPrefix 图片前缀
/// @param quality 质量 1-5
/// @param finishBlock finish
- (FWMediaState)snapshotVideo:(NSString *)videoPath startTime:(CGFloat)startTime fps:(NSInteger)fps picDirectory:(NSString *)picDirectory picPrefix:(NSString *)picPrefix quality:(NSInteger)quality finishBlock:(void (^)(BOOL success))finishBlock; {
    if (!picDirectory) {
        return FWMediaStateErrorPath;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:picDirectory]) {
        [[NSFileManager defaultManager] removeItemAtPath:picDirectory error:nil];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:picDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *picPath;
    NSMutableString *mCommand = [[NSMutableString alloc] initWithFormat:@"-ss %f -i %@ -y -f image2 -q:v %ld ", startTime, videoPath, (long)quality];
    if (fps > 0) {
        [mCommand appendFormat:@"-r %ld ", (long)fps];
        picPath = [picDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%%d.jpg", picPrefix]];
    } else {
        [mCommand appendString:@"-vframes 1 "];
        picPath = [picDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", picPrefix]];
    }
    [mCommand appendString:picPath];

    FFmpegSession *session = [FFmpegKit execute:[NSString stringWithString:mCommand]];
    ReturnCode *returnCode = [session getReturnCode];
    if ([returnCode isSuccess]) {
        NSLog(@"Encode completed successfully.\n");
    } else {
        NSLog(@"Encode failed with rc=%d\n", [returnCode getValue]);
    }
    
    if (finishBlock) {
        finishBlock([returnCode isSuccess]);
    }
        
    
    return FWMediaStateSuccess;
}

/// 把图片合到视频上
/// @param videoPath 视频地址
/// @param toPath 目标地址
/// @param imagesArray 图片配置数组
/// {
///     "image" : "xxxx",   // 图片地址
///     "x" : 123,          // 左上角x
///     "y" : 232,          // 左上角y
///     "start" : 10.34,    // 起始时间
///     "end"   : 16.3      // 结束时间，必须大于start
/// }
/// @param finishBlock finish
- (FWMediaState)drawImagesOnVideo:(NSString *)videoPath toPath:(NSString *)toPath imagesArray:(NSArray <NSDictionary *> *)imagesArray timeProgress:(void (^)(NSTimeInterval time))timeProgress finishBlock:(void (^)(BOOL success))finishBlock {
    if (!toPath) {
        return FWMediaStateErrorPath;
    }
    
    if (self.asyncId > 0) {
        return FWMediaStatePreviousTaskNotFinish;
    }
    
    self.progressTimeBlock = timeProgress;
    self.runResultBlock = finishBlock;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:toPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:toPath error:nil];
    }
    
    NSString *dirPath = [toPath stringByDeletingLastPathComponent];
    BOOL isDir = NO;
    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDir];
    if (isExist && isDir) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // 筛选有效的配置
    NSMutableArray * __block mArr = [[NSMutableArray alloc] init];
    [imagesArray enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            CGFloat startTime = [obj[@"start"] floatValue];
            CGFloat endTime = [obj[@"end"] floatValue];
            NSString *imagePath = obj[@"image"];
            BOOL fileExist = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
            if (endTime > startTime && fileExist) {
                [mArr addObject:obj];
            }
        }
    }];
    
    NSMutableString *imagesCommand = [[NSMutableString alloc] init];
    for (NSInteger i = 0; i < mArr.count; i ++) {
        NSDictionary *dic = mArr[i];
        NSString *imagePath = dic[@"image"];
        NSString *imgStr = [NSString stringWithFormat:@"movie=%@[wm%ld];", imagePath, (long)i];
        [imagesCommand appendString:imgStr];
    }
    
    NSString *preIn = @"[in]";
    for (NSInteger i = 0; i < mArr.count; i ++) {
        [imagesCommand appendString:preIn];
        
//        [wm1] overlay=main_w-overlay_w-10:main_h-overlay_h-10:enable='between(t,1,4)'[a1];
        NSDictionary *dic = mArr[i];
        CGFloat startTime = [dic[@"start"] floatValue];
        CGFloat endTime = [dic[@"end"] floatValue];
        CGFloat x = [dic[@"x"] floatValue];
        CGFloat y = [dic[@"y"] floatValue];
        NSString *overlayStr = [NSString stringWithFormat:@"[wm%ld]overlay=%f:%f:enable='between(t,%f,%f)'", (long)i, x, y, startTime, endTime];
        [imagesCommand appendString:overlayStr];
        if (i == mArr.count - 1) {
            [imagesCommand appendString:@"[out]"];
        } else {
            preIn = [NSString stringWithFormat:@"[a%ld]", (long)i];
            [imagesCommand appendString:preIn];
            [imagesCommand appendString:@";"];
        }
    }
    
    NSString *command = [NSString stringWithFormat:@"-i %@ -vf \"%@\" %@", videoPath, imagesCommand, toPath];
    WEAKSELF
    [FFmpegKitConfig enableLogCallback:^(Log *log) {
        [weakSelf logCallback:[log getSessionId] :[log getLevel] :[log getMessage]];
    }];
    FFmpegSession *session = [FFmpegKit executeAsync:command withExecuteCallback:^(id<Session> session) {
        ReturnCode *code = [session getReturnCode];
        if (weakSelf.asyncId == [session getSessionId] && code) {
            weakSelf.runResultBlock([code isSuccess]);
            weakSelf.runResultBlock = nil;
            weakSelf.asyncId = 0;
        }
    }];
    self.asyncId = [session getSessionId];
    return FWMediaStateSuccess;
}

#pragma mark - log delegate

- (void)logCallback:(long)executionId :(int)level :(NSString *)message {
    if (self.progressTimeBlock &&
        [message containsString:@"frame"] &&
        [message containsString:@"fps"] &&
        [message containsString:@"size"] &&
        [message containsString:@"time"] &&
        [message containsString:@"bitrate"] &&
        [message containsString:@"speed"]) {
        //消息包含信息判断
        NSArray *messageArr = [message componentsSeparatedByString:@" "];
        for (NSString *str in messageArr) {
            if (str.length >= 16 && [str containsString:@"time="]) {
                NSString *timeStr = [str substringFromIndex:5];
                CGFloat timeSecend = 0.0f;
                NSArray *arr = [timeStr componentsSeparatedByString:@"."];
                if (arr.count == 2) {
                    NSString *ttt = [arr firstObject]; //00:00:00
                    CGFloat nss = [[arr lastObject] doubleValue] / 100.0f; // 111
                    NSArray *timeArray = [ttt componentsSeparatedByString:@":"];
                    NSInteger i = 0;
                    while (i < 3) {
                        NSInteger tt = [timeArray[timeArray.count - i - 1] integerValue];
                        if (i == 0) {
                            timeSecend += tt * 1.0;
                        } else if (i == 1) {
                            timeSecend += tt * 60.0;
                        } else if (i == 2) {
                            timeSecend += tt * 3600.0;
                        }
                        i++;
                    }
                    timeSecend += nss;
                    self.progressTimeBlock(timeSecend);
                }//end  if (arr.count == 2)
            }//end if (str.length >= 16)
        }//end for messageArr
    }
    
    NSLog(@"message is %@", message);
}

/**
 取消当前执行的session，通过asyncId
 */
- (void)cancel {
    if (self.asyncId > 0) {
        [FFmpegKit cancel:self.asyncId];
    } else {
        [FFmpegKit cancel];
    }
}

#pragma mark - Private Method




@end
