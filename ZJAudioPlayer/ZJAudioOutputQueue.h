//
//  ZJAudioOutputQueue.h
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/7.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface ZJAudioOutputQueue : NSObject

@property (nonatomic, assign) BOOL available;
@property (nonatomic, assign) AudioStreamBasicDescription format;
@property (nonatomic, assign) float volume;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) NSTimeInterval playedTime;


- (instancetype)initWithFormat:(AudioStreamBasicDescription)format withBufferSize:(UInt32)bufferSize magicCookie:(NSData *)magicCookie;

- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof;

- (BOOL)pause;
- (BOOL)resume;

- (BOOL)stop:(BOOL)immediately;/**<if pass YES,the queue will immediately be stoped, if pass NO,the queue will be stopped after all buffers are flushed(as the -flush)*/

- (BOOL)reset;/**<use when seek*/

- (BOOL)flush;

- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError **)outError;
- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError **)outError;
- (BOOL)setParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue )value error:(NSError **)ourError;
- (BOOL)getParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue *)value error:(NSError **)outError;

@end
