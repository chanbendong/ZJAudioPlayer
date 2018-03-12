//
//  ZJAudioPlayer.h
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/5.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

typedef NS_ENUM(NSUInteger, ZJAudioPlayerStatus)
{
    ZJAudioPlayerStatusStopped = 0,
    ZJAudioPlayerStatusPlaying = 1,
    ZJAudioPlayerStatusWaiting = 2,
    ZJAudioPlayerStatusPaused = 3,
    ZJAudioPlayerStatusFlushing = 4,
};

@interface ZJAudioPlayer : NSObject

@property (nonatomic,copy) NSString *filePath;
@property (nonatomic,assign) AudioFileTypeID fileType;

@property (nonatomic,assign) ZJAudioPlayerStatus status;
@property (nonatomic,assign) BOOL isPlayingOrWaiting;
@property (nonatomic,assign) BOOL failed;

@property (nonatomic,assign) NSTimeInterval progress;
@property (nonatomic,assign) NSTimeInterval duration;


- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType;

- (void)play;
- (void)pause;
- (void)stop;
@end
