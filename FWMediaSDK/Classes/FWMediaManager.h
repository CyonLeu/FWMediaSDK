//
//  FWMediaManager.h
//  FWMediaSDK
//
//  Created by Yong Liu on 2021/11/24.
//
// 该类主要为解决多媒体处理类
// 主要包含，音视频的裁剪与合成，音视频抽离，添加水印，格式转换等

#import <Foundation/Foundation.h>

#import "FWMediaConstant.h"

NS_ASSUME_NONNULL_BEGIN

@interface FWMediaManager : NSObject


+ (instancetype)sharedManager;

#pragma mark - audioHandle -
/**
 根据时间段来裁剪音频文件:
 把一段音频裁剪为多段，根据数组时间点，
 并放到toPathDir目录下，文件名以index字段来命名；
 timeArray：多个NSDictionary对象，
 包含三个值{"index":"1", "beginTime":@(1.3), "endTime":@(3.0)}
 */
- (void)cutAudioFile:(NSString *)filePath
              toPath:(NSString *)toPathDir
           timeArray:(NSArray *)timeArray;

#pragma mark - VideoHandle -
/**
 根据时间段来裁剪单个媒体文件：裁剪文件片段，可裁剪音频或视频
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
                 finishBlock:(void (^)(BOOL success))finishBlock;

/// 压缩视频
/// @param videoPath 视频地址
/// @param toPath 结果地址
/// @param finishBlock finish
- (FWMediaState)compressVideo:(NSString *)videoPath toPath:(NSString *)toPath finishBlock:(void (^)(BOOL success))finishBlock;

/// 从视频中抽取用来识别字幕的音频
/// @param videoPath 视频地址
/// @param path 音频地址
/// @param finishBlock finish
- (FWMediaState)extractSrtAudioFromVideo:(NSString *)videoPath toPath:(NSString *)path finishBlock:(void (^)(BOOL success))finishBlock;

/// 合成音频
/// @param paths 资源文件
/// @param outputPath 输出地址
- (int)compositionMediaWithPaths:(NSArray *)paths times:(NSArray *)times outputPath:(NSString *)outputPath;

/// 音频文件转aac
/// @param audioPath 音频文件地址
/// @param cafPath 目标文件地址
- (FWMediaState)convertAudio:(NSString *)audioPath toCafPath:(NSString *)cafPath;

#pragma mark - 音频信息：根据音频地址获取相关信息 -

/// 获取音频信息
/// @param path 音频地址
- (NSDictionary *)getMediaInfoWithPath:(NSString *)path  ;

/// 获取音频分贝
/// @param filePath 音频地址
- (CGFloat)getMediaDecibelWithFilePath:(NSString *)filePath;

/// 获取音频分贝中位数
/// @param filePath 音频地址
- (CGFloat)getMediaDecibelMedianWithFilePath:(NSString *)filePath;

/// 修改音频分贝
/// @param inputPath 输入音频地址
/// @param outputPath 输出音频地址
/// @param decibel 修改的分贝大小
- (int)changeMediaDecibelWithInputFilePath:(NSString *)inputPath outputPath:(NSString *)outputPath decibel:(CGFloat)decibel;

#pragma mark - 获取图片帧 或 添加水印

/// 视频截图
/// @param videoPath 视频地址
/// @param startTime 截图起始时间
/// @param fps 每秒多少张
/// @param picDirectory 图片保存目录
/// @param picPrefix 图片前缀
/// @param quality 质量 1-5
/// @param finishBlock finish
/// 注：此方法尽可能在主线程执行，否则可能引起255错误
/// 另外，间隔截图的第一张和第二张是重复的，所以取值从第二张起
/// -vf fps=n 参数不好用，截的是帧间隔中位的图片
- (FWMediaState)snapshotVideo:(NSString *)videoPath startTime:(CGFloat)startTime fps:(NSInteger)fps picDirectory:(NSString *)picDirectory picPrefix:(NSString *)picPrefix quality:(NSInteger)quality finishBlock:(void (^)(BOOL success))finishBlock;

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
- (FWMediaState)drawImagesOnVideo:(NSString *)videoPath toPath:(NSString *)toPath imagesArray:(NSArray <NSDictionary *> *)imagesArray timeProgress:(void (^)(NSTimeInterval time))timeProgress finishBlock:(void (^)(BOOL success))finishBlock;


/**
 取消当前执行的session，通过asyncId
 */
- (void)cancel;


@end

NS_ASSUME_NONNULL_END
