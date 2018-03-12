//
//  ZJAudioFileStream.h
//  AudioStream
//
//  Created by 吴孜健 on 2018/2/23.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "ZJParseAudioData.h"

@class ZJAudioFileStream;
@protocol ZJAudioFileStreamDelegate <NSObject>
@required
- (void)audioFileStream:(ZJAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData;
@optional
- (void)audioFileStreamReadyToProducePackets:(ZJAudioFileStream *)audioFileStream;
@end

@interface ZJAudioFileStream : NSObject

@property (nonatomic, assign) AudioFileTypeID fileType;
@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) BOOL readyToProducePackets;
@property (nonatomic, weak) id<ZJAudioFileStreamDelegate> delegate;

@property (nonatomic, assign) AudioStreamBasicDescription format;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) UInt32 bitRate;
@property (nonatomic, assign) UInt32 maxPacketSize;
@property (nonatomic, assign) UInt64 audioDataByteCount;


- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error;

- (BOOL)parseData:(NSData *)data error:(NSError **)error;

- (SInt64)seekToTime:(NSTimeInterval *)time;

- (NSData *)fetchMagicCookie;

- (void)close;

@end
