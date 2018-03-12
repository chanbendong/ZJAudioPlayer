//
//  ZJAudioFile.h
//  ZJAudioFile
//
//  Created by 吴孜健 on 2018/2/26.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "ZJParseAudioData.h"

@interface ZJAudioFile : NSObject

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) AudioFileTypeID fileType;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) AudioStreamBasicDescription format;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) UInt32 bitRate;
@property (nonatomic, assign) UInt32 maxPacketSize;
@property (nonatomic, assign) UInt64 audioDataByteCount;

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType;
- (NSArray *)parseData:(BOOL *)isErr;
- (NSData *)fetchMagicCookie;
- (void)seekToTime:(NSTimeInterval)time;
- (void)close;

@end
