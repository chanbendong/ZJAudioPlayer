//
//  ZJAudioBuffer.m
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/5.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import "ZJAudioBuffer.h"

@interface ZJAudioBuffer()

@property (nonatomic, strong) NSMutableArray *bufferBlockArray;
@property (nonatomic, assign) UInt32 bufferedSize;

@end

@implementation ZJAudioBuffer

+ (instancetype)buffer
{
    return [[self alloc]init];
}

- (instancetype)init
{
    if (self = [super init]) {
        _bufferBlockArray = [[NSMutableArray alloc]init];
    }
    return self;
}

- (BOOL)hasData
{
    return _bufferBlockArray.count>0;
}

- (UInt32)bufferedSize
{
    return _bufferedSize;
}

- (void)enqueueFromDataArray:(NSArray *)dataArray
{
    for (ZJParseAudioData *data in dataArray) {
        [self enqueueData:data];
    }
}

- (void)enqueueData:(ZJParseAudioData *)data
{
    if ([data isKindOfClass:[ZJParseAudioData class]]) {
        [_bufferBlockArray addObject:data];
        _bufferedSize += data.data.length;
    }
}


- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions
{
    if (requestSize == 0 && _bufferBlockArray.count == 0)
    {
        return nil;
    }
    
    SInt64 size = requestSize;
    int i = 0;
    for (i = 0; i < _bufferBlockArray.count; i++) {
        ZJParseAudioData *block = _bufferBlockArray[i];
        SInt64 dataLength = [block.data length];
        if (size > dataLength) {
            size -= dataLength;
        }else{
            if (size < dataLength) {
                i--;
            }
            break;
        }
    }
    if (i < 0) {
        return nil;
    }
    
    UInt32 count = (i >= _bufferBlockArray.count)?(UInt32)_bufferBlockArray.count:(i+1);
    *packetCount = count;
    
    if (count == 0) {
        return nil;
    }
    
    if (descriptions != NULL) {
        *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*count);
    }
    
    NSMutableData *retData = [[NSMutableData alloc]init];
    for (int j = 0; j < count; j++) {
        ZJParseAudioData *block = _bufferBlockArray[j];
        if (descriptions != NULL) {
            AudioStreamPacketDescription desc = block.packetDescription;
            desc.mStartOffset = [retData length];
            (*descriptions)[j] = desc;
        }
        [retData appendData:block.data];
    }
    
    NSRange removeRnage = NSMakeRange(0, count);
    [_bufferBlockArray removeObjectsInRange:removeRnage];
    _bufferedSize -= retData.length;
    
    return retData;
}

- (void)clean
{
    _bufferedSize = 0;
    [_bufferBlockArray removeAllObjects];
    
}

- (void)dealloc
{
    [_bufferBlockArray removeAllObjects];
}
@end
