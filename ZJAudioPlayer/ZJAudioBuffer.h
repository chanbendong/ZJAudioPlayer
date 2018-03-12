//
//  ZJAudioBuffer.h
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/5.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "ZJParseAudioData.h"

@interface ZJAudioBuffer : NSObject

+ (instancetype)buffer;

- (void)enqueueData:(ZJParseAudioData *)data;
- (void)enqueueFromDataArray:(NSArray *)dataArray;

- (BOOL)hasData;
- (UInt32)bufferedSize;

- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions;

- (void)clean;

@end
