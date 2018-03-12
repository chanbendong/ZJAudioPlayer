//
//  ZJAudioOutputQueue.m
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/7.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import "ZJAudioOutputQueue.h"
#import <pthread.h>

const int ZJAudioQueueBufferCount = 2;

@interface ZJAudioQueueBuffer : NSObject
@property (nonatomic, assign) AudioQueueBufferRef buffer;
@end
@implementation ZJAudioQueueBuffer
@end

@interface ZJAudioOutputQueue()

@property (nonatomic, assign) AudioQueueRef audioQueue;
@property (nonatomic, strong) NSMutableArray *buffers;
@property (nonatomic, strong) NSMutableArray *reusableBuffers;
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) pthread_mutex_t mutex;
@property (nonatomic, assign) pthread_cond_t cond;


@end

@implementation ZJAudioOutputQueue


- (instancetype)initWithFormat:(AudioStreamBasicDescription)format withBufferSize:(UInt32)bufferSize magicCookie:(NSData *)magicCookie
{
    if (self = [super init]) {
        _format = format;
        _volume = 1.f;
        _bufferSize = bufferSize;
        _buffers = [NSMutableArray array];
        _reusableBuffers = [NSMutableArray array];
        [self _createAudioOutputQueue:magicCookie];
        [self mutexInit];
        
    }
    return self;
}

- (void)dealloc
{
    [self disposeAudioOutputQueue];
    [self mutexDestory];
}

#pragma mark - error
- (void)errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

#pragma mark - mutex
- (void)mutexInit
{
    pthread_mutex_init(&_mutex, NULL);
    pthread_cond_init(&_cond, NULL);
}

- (void)mutexDestory
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}

- (void)mutexWait
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_wait(&_cond, &_mutex);
    pthread_mutex_unlock(&_mutex);
}

- (void)mutexSignal
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}


#pragma mark - audio queue
- (void)_createAudioOutputQueue:(NSData *)magicCookie
{
    OSStatus status = AudioQueueNewOutput(&_format, ZJAdudioQueueOutputCallback, (__bridge void *)self, NULL, NULL, 0, &_audioQueue);
    if (status != noErr) {
        _audioQueue = NULL;
        return;
    }

    status = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning, ZJAudioQueuePropertyCallback, (__bridge void *)self);
    if (status != noErr) {
        AudioQueueDispose(_audioQueue, YES);
        _audioQueue = NULL;
        return;
    }
    
    if (_buffers.count == 0) {
        for (int i = 0; i < ZJAudioQueueBufferCount; ++i) {
            AudioQueueBufferRef buffer;
            status = AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
            if (status != noErr) {
                AudioQueueDispose(_audioQueue, YES);
                _audioQueue = NULL;
                return;
            }
            
            ZJAudioQueueBuffer *bufferObj = [[ZJAudioQueueBuffer alloc]init];
            bufferObj.buffer = buffer;
            [_buffers addObject: bufferObj];
            [_reusableBuffers addObject:bufferObj];
        }
    }
    
#if TARGET_OS_IPHONE
    UInt32 property = kAudioQueueHardwareCodecPolicy_PreferSoftware;
    [self setProperty:kAudioQueueProperty_HardwareCodecPolicy dataSize:sizeof(property) data:&property error:NULL];
#endif
    
    if (magicCookie) {
        AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, [magicCookie bytes], (UInt32)[magicCookie length]);
    }
    
    [self setVolumeParameter];
    
}

- (void)disposeAudioOutputQueue
{
    if (_audioQueue != NULL) {
        AudioQueueDispose(_audioQueue, true);
        _audioQueue = NULL;
    }
}

- (BOOL)start
{
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    _started = status == noErr;
    return _started;
}

- (BOOL)resume
{
    return [self start];
}

- (BOOL)pause
{
    OSStatus status = AudioQueuePause(_audioQueue);
    _started = NO;
    return status == noErr;
}

- (BOOL)reset
{
    OSStatus status = AudioQueueReset(_audioQueue);
    return status == noErr;
}

- (BOOL)flush
{
    return AudioQueueFlush(_audioQueue) == noErr;
}

- (BOOL)stop:(BOOL)immediately
{
    OSStatus status = noErr;
    if (immediately) {
        status = AudioQueueStop(_audioQueue, true);
    }else{
        status = AudioQueueStop(_audioQueue, false);
    }
    _started = NO;
    _playedTime = 0;
    return status == noErr;
}

- (BOOL)playData:(NSData *)data packetCount:(UInt32)packetCount packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions isEof:(BOOL)isEof
{
    if ([data length] > _bufferSize) {
        return NO;
    }
    
    if (_reusableBuffers.count == 0) {
        if (!_started && ![self start]) {
            return NO;
        }
        [self mutexWait];
    }
    
    ZJAudioQueueBuffer *bufferObj = [_reusableBuffers firstObject];
    [_reusableBuffers removeObject:bufferObj];
    if (!bufferObj) {
        AudioQueueBufferRef buffer;
        OSStatus status = AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
        if (status == noErr) {
            bufferObj = [[ZJAudioQueueBuffer alloc]init];
            bufferObj.buffer = buffer;
        }else{
            return NO;
        }
    }
    
    memcpy(bufferObj.buffer->mAudioData, [data bytes], [data length]);
    bufferObj.buffer->mAudioDataByteSize = (UInt32)[data length];
    
    OSStatus status = AudioQueueEnqueueBuffer(_audioQueue, bufferObj.buffer, packetCount, packetDescriptions);
    
    if (status == noErr) {
        if (_reusableBuffers.count == 0 || isEof) {
            if (!_started && ![self start]) {
                return NO;
            }
        }
    }
    return status == noErr;
}

- (BOOL)setProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32)dataSize data:(const void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueSetProperty(_audioQueue, propertyID, data, dataSize);
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)getProperty:(AudioQueuePropertyID)propertyID dataSize:(UInt32 *)dataSize data:(void *)data error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetProperty(_audioQueue, propertyID, data, dataSize);
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

- (BOOL)setParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue)value error:(NSError *__autoreleasing *)ourError
{
    OSStatus status = AudioQueueSetParameter(_audioQueue, parameterId, value);
    [self errorForOSStatus:status error:ourError];
    return status == noErr;
}

- (BOOL)getParameter:(AudioQueueParameterID)parameterId value:(AudioQueueParameterValue *)value error:(NSError *__autoreleasing *)outError
{
    OSStatus status = AudioQueueGetParameter(_audioQueue, parameterId, value);
    [self errorForOSStatus:status error:outError];
    return status == noErr;
}

#pragma mark - property
- (NSTimeInterval)playedTime
{
    if (_format.mSampleRate == 0) {
        return 0;
    }
    
    AudioTimeStamp time;
    OSStatus status = AudioQueueGetCurrentTime(_audioQueue, NULL, &time, NULL);
    if (status == noErr) {
        _playedTime = time.mSampleTime/_format.mSampleRate;
    }
    return _playedTime;
}

- (BOOL)available
{
    return _audioQueue != NULL;
}

- (void)setVolume:(float)volume
{
    _volume = volume;
    [self setVolumeParameter];
}

- (void)setVolumeParameter
{
    [self setParameter:kAudioQueueParam_Volume value:_volume error:NULL];
}



#pragma mark - call back
static void ZJAdudioQueueOutputCallback(void *inclientData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    ZJAudioOutputQueue *audioOutputQueue = (__bridge ZJAudioOutputQueue *)inclientData;
    [audioOutputQueue handleAudioQueueOutputCallback:inAQ buffer:inBuffer];
}

- (void)handleAudioQueueOutputCallback:(AudioQueueRef)audioQueue buffer:(AudioQueueBufferRef)buffer
{
    for (int i = 0; i < _buffers.count; i++) {
        if (buffer == [_buffers[i] buffer]) {
            [_reusableBuffers addObject:_buffers[i]];
            break;
        }
    }
    [self mutexSignal];
}

static void ZJAudioQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    ZJAudioOutputQueue *audioQueue = (__bridge ZJAudioOutputQueue *)inUserData;
    [audioQueue handleAudioQueuePropertyCallBack:inAQ propetyId:inID];
}

- (void)handleAudioQueuePropertyCallBack:(AudioQueueRef)audioQueue propetyId:(AudioQueuePropertyID)propertyId
{
    if (propertyId == kAudioQueueProperty_IsRunning) {
        UInt32 isRuning = 0;
        UInt32 size = sizeof(isRuning);
        AudioQueueGetProperty(audioQueue, propertyId, &isRuning, &size);
        _isRunning = isRuning;
    }
}

@end
