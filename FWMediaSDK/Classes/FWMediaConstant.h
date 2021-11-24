//
//  FWMediaConstant.h
//  FWMediaSDK
//
//  Created by Yong Liu on 2021/11/24.
//

//项目中的常量，枚举定义

/**
 多媒体操作错误等类型
 */
typedef NS_ENUM(NSUInteger, FWMediaState) {
    FWMediaStateSuccess = 0,
    FWMediaStateError = 1,
    FWMediaStateErrorPath = 2,
    FWMediaStatePreviousTaskNotFinish = 3, // 上一个任务未结束
};


typedef NS_ENUM(NSUInteger, FWMediaType) {
    FWMediaTypeUnknown = -1,//未知
    FWMediaTypeVideo = 0, //视频
    FWMediaTypeAudio = 1, //音频
};
