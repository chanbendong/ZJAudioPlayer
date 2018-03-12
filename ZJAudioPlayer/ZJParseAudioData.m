//
//  ZJParseAudioData.m
//  AudioStream
//
//  Created by 吴孜健 on 2018/2/23.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import "ZJParseAudioData.h"

@implementation ZJParseAudioData

@synthesize  data = _data;
@synthesize  packetDescription = _packetDescription;

+ (instancetype)parsedAudioDataWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packetDescription
{
    return [[self alloc]initWithBytes:bytes packetDescription:packetDescription];
}

- (instancetype)initWithBytes:(const void *)bytes packetDescription:(AudioStreamPacketDescription)packDescription
{
    if (bytes == NULL || packDescription.mDataByteSize == 0) {
        return nil;
    }
    if (self = [super init]) {
        _data = [NSData dataWithBytes:bytes length:packDescription.mDataByteSize];
        _packetDescription = packDescription;
    }
    return self;
}

@end
