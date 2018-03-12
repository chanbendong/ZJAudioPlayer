//
//  ZJParseAudioData.h
//  AudioStream
//
//  Created by 吴孜健 on 2018/2/23.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

@interface ZJParseAudioData : NSObject

@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) AudioStreamPacketDescription packetDescription;

+ (instancetype)parsedAudioDataWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription;

@end
