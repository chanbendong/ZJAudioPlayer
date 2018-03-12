//
//  ZJAudioPlayer.m
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/5.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import "ZJAudioPlayer.h"
#import "ZJAudioFile.h"
#import "ZJAudioFileStream.h"
#import "ZJAudioBuffer.h"
#import "ZJAudioOutputQueue.h"
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>

@interface ZJAudioPlayer()<ZJAudioFileStreamDelegate>

@property (nonatomic, strong) NSThread *thread;
@property (nonatomic, assign) pthread_mutex_t mutex;
@property (nonatomic, assign) pthread_cond_t cond;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, assign) unsigned long long offset;
@property (nonatomic, assign) UInt32 bufferSize;
@property (nonatomic, strong) ZJAudioBuffer *buffer;
@property (nonatomic, strong) ZJAudioFile *audioFile;
@property (nonatomic, strong) ZJAudioFileStream *audioFileStream;
@property (nonatomic, strong) ZJAudioOutputQueue *audioQueue;
@property (nonatomic, strong) NSFileHandle *fileHandler;
@property (nonatomic, assign) SInt64 packetOffset;
@property (nonatomic, assign) SInt64 dataOffset;
@property (nonatomic, assign) NSTimeInterval packetDuration;
@property (nonatomic, assign) AudioFileID audioFileID;

@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL pauseRequired;
@property (nonatomic, assign) BOOL stopRequired;
@property (nonatomic, assign) BOOL pauseByInterrupt;
@property (nonatomic, assign) BOOL usingAudioFile;
@property (nonatomic, assign) BOOL seekRequired;
@property (nonatomic, assign) NSTimeInterval seekTime;
@property (nonatomic, assign) NSTimeInterval timingOffset;

@end

@implementation ZJAudioPlayer

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType
{
    if (self = [super init]) {
        _status = ZJAudioPlayerStatusStopped;
        _filePath = filePath;
        _fileType = fileType;
        
        
        _fileHandler = [NSFileHandle fileHandleForReadingAtPath:_filePath];
        _fileSize = [[[NSFileManager defaultManager]attributesOfItemAtPath:_filePath error:nil] fileSize];
        if (_fileHandler && _fileSize>0) {
            _buffer = [ZJAudioBuffer buffer];
        }else{
            [_fileHandler closeFile];
            _failed = YES;
        }
    }
    return self;
}

- (void)dealloc
{
    [self cleanUp];
    [_fileHandler closeFile];
}

- (void)cleanUp
{
    //resetFile
    _offset = 0;
    [_fileHandler seekToFileOffset:0];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    
    //clean buffer
    [_buffer clean];
    _usingAudioFile= NO;
    
    //close audioFile
    [_audioFile close];
    _audioFile = nil;
    
    //close audiofilestream
    [_audioFileStream close];
    _audioFileStream = nil;
    
    //stop audioQueue
    [_audioQueue stop:YES];
    _audioQueue = nil;
    
    //destroy mutex &cond
    [self mutexDestroy];
    
    _started = NO;
    _timingOffset = 0;
    _seekTime = 0;
    _seekRequired = NO;
    _pauseRequired = NO;
    _stopRequired = NO;
    
    //reset status
    [self setStatusInternal:ZJAudioPlayerStatusStopped];
}

#pragma mark - status
- (BOOL)isPlayingOrWaiting
{
    return self.status == ZJAudioPlayerStatusWaiting || self.status == ZJAudioPlayerStatusPlaying || self.status == ZJAudioPlayerStatusFlushing;
}

- (ZJAudioPlayerStatus)status
{
    return _status;
}

- (void)setStatusInternal:(ZJAudioPlayerStatus)status
{
    if (_status == status) {
        return;
    }
    
    [self willChangeValueForKey:@"status"];
    _status = status;
    [self didChangeValueForKey:@"status"];
}

#pragma mark - mutex
- (void)mutexInit
{
    pthread_mutex_init(&_mutex, NULL);
    pthread_cond_init(&_cond, NULL);
}

- (void)mutexDestroy
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

#pragma mark - thread

- (BOOL)createaAudioQueue
{
    if (_audioQueue) {
        return YES;
    }
    NSTimeInterval duration = self.duration;
    UInt64 audioDataByteCount = _usingAudioFile?_audioFile.audioDataByteCount:_audioFileStream.audioDataByteCount;
    _bufferSize = 0;
    if (duration != 0) {
        _bufferSize = (0.2/duration)*audioDataByteCount;
    }
    if (_bufferSize>0) {
        AudioStreamBasicDescription format = _usingAudioFile?_audioFile.format:_audioFileStream.format;
        NSData *magicCookie = _usingAudioFile?[_audioFile fetchMagicCookie]:[_audioFileStream fetchMagicCookie];
        _audioQueue = [[ZJAudioOutputQueue alloc]initWithFormat:format withBufferSize:_bufferSize magicCookie:magicCookie];
        if (!_audioQueue.available) {
            _audioQueue = nil;
            return NO;
        }
    }
    return YES;
}

- (void)threadMain
{
    _failed = YES;
    NSError *error = nil;
    //set AVAudioSession category
    if ([[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback error:NULL]) {
        //active AVAudioSession
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruptionHandler:) name:AVAudioSessionInterruptionNotification object:nil];
        if ([[AVAudioSession sharedInstance] setActive:YES error:NULL]) {
            //create audioFileStream
            _audioFileStream = [[ZJAudioFileStream alloc]initWithFileType:_fileType fileSize:_fileSize error:&error];
            if (!error) {
                _failed = NO;
                _audioFileStream.delegate = self;
            }
        }
    }
    if (_failed) {
        [self cleanUp];
        return;
    }
    
    [self setStatusInternal:ZJAudioPlayerStatusWaiting];
    BOOL isEof = NO;
    while (self.status != ZJAudioPlayerStatusStopped && !_failed && _started) {
        @autoreleasepool
        {
            //read file & parse
            if (_usingAudioFile)
            {
                if (!_audioFile)
                {
                    _audioFile = [[ZJAudioFile alloc] initWithFilePath:_filePath fileType:_fileType];
                }
                [_audioFile seekToTime:_seekTime];
                if ([_buffer bufferedSize] < _bufferSize || !_audioQueue)
                {
                    NSArray *parsedData = [_audioFile parseData:&isEof];
                    if (parsedData)
                    {
                        [_buffer enqueueFromDataArray:parsedData];
                    }
                    else
                    {
                        _failed = YES;
                        break;
                    }
                }
            }
            else
            {
                if (_offset < _fileSize && (!_audioFileStream.readyToProducePackets || [_buffer bufferedSize] < _bufferSize || !_audioQueue))
                {
                    NSData *data = [_fileHandler readDataOfLength:1000];
                    _offset += [data length];
                    if (_offset >= _fileSize)
                    {
                        isEof = YES;
                    }
                    [_audioFileStream parseData:data error:&error];
                    if (error)
                    {
                        _usingAudioFile = YES;
                        continue;
                    }
                }
            }
            
            
            
            if (_audioFileStream.readyToProducePackets || _usingAudioFile)
            {
                if (![self createaAudioQueue])
                {
                    _failed = YES;
                    break;
                }
                
                if (!_audioQueue)
                {
                    continue;
                }
                
                if (self.status == ZJAudioPlayerStatusFlushing && !_audioQueue.isRunning)
                {
                    break;
                }
                
                //stop
                if (_stopRequired)
                {
                    _stopRequired = NO;
                    _started = NO;
                    [_audioQueue stop:YES];
                    break;
                }
                
                //pause
                if (_pauseRequired)
                {
                    [self setStatusInternal:ZJAudioPlayerStatusPaused];
                    [_audioQueue pause];
                    [self mutexWait];
                    _pauseRequired = NO;
                }
                
                //play
                if ([_buffer bufferedSize] >= _bufferSize || isEof)
                {
                    UInt32 packetCount;
                    AudioStreamPacketDescription *desces = NULL;
                    NSData *data = [_buffer dequeueDataWithSize:_bufferSize packetCount:&packetCount descriptions:&desces];
                    if (packetCount != 0)
                    {
                        [self setStatusInternal:ZJAudioPlayerStatusPlaying];
                        _failed = ![_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:isEof];
                        free(desces);
                        if (_failed)
                        {
                            break;
                        }
                        
                        if (![_buffer hasData] && isEof && _audioQueue.isRunning)
                        {
                            [_audioQueue stop:NO];
                            [self setStatusInternal:ZJAudioPlayerStatusFlushing];
                        }
                    }
                    else if (isEof)
                    {
                        //wait for end
                        if (![_buffer hasData] && _audioQueue.isRunning)
                        {
                            [_audioQueue stop:NO];
                            [self setStatusInternal:ZJAudioPlayerStatusFlushing];
                        }
                    }
                    else
                    {
                        _failed = YES;
                        break;
                    }
                }
                
                //seek
                if (_seekRequired && self.duration != 0)
                {
                    [self setStatusInternal:ZJAudioPlayerStatusWaiting];
                    
                    _timingOffset = _seekTime - _audioQueue.playedTime;
                    [_buffer clean];
                    if (_usingAudioFile)
                    {
                        [_audioFile seekToTime:_seekTime];
                    }
                    else
                    {
                        _offset = [_audioFileStream seekToTime:&_seekTime];
                        [_fileHandler seekToFileOffset:_offset];
                    }
                    _seekRequired = NO;
                    [_audioQueue reset];
                }
            }
        }
    }
    [self cleanUp];
}

#pragma mark -interrupt
- (void)interruptionHandler:(NSNotification *)notification
{
    UInt32 interruptionState = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntValue];
    if (interruptionState == AVAudioSessionInterruptionTypeBegan) {
        _pauseByInterrupt = YES;
        [_audioQueue pause];
        [self setStatusInternal:ZJAudioPlayerStatusPaused];
    }else if (interruptionState == AVAudioSessionInterruptionTypeEnded){
        AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntValue];
        if (interruptionType == AVAudioSessionInterruptionOptionShouldResume) {
            if (self.status == ZJAudioPlayerStatusPaused && _pauseByInterrupt) {
                if ([[AVAudioSession sharedInstance] setActive:YES error:NULL]) {
                    [self play];
                }
            }
        }
    }
}

#pragma mark - parser
- (void)audioFileStream:(ZJAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData
{
    [_buffer enqueueFromDataArray:audioData];
}

#pragma mark - progress
- (NSTimeInterval)progress
{
    if (_seekRequired) {
        return _seekTime;
    }
    return _timingOffset+_audioQueue.playedTime;
}

- (void)setProgress:(NSTimeInterval)progress
{
    _seekRequired = YES;
    _seekTime = progress;
}

- (NSTimeInterval)duration
{
    NSTimeInterval time =  _usingAudioFile?_audioFile.duration:_audioFileStream.duration;
    return time;
}

#pragma mark - play
- (void)play
{
    if (!_started) {
        _started = YES;
        [self mutexInit];
        _thread = [[NSThread alloc]initWithTarget:self selector:@selector(threadMain) object:nil];
        [_thread start];
    }else{
        if (_status == ZJAudioPlayerStatusPaused || _pauseRequired) {
            _pauseByInterrupt = NO;
            _pauseRequired = NO;
            if ([[AVAudioSession sharedInstance]setActive:YES error:NULL]) {
                [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback error:NULL];
            }
        }
    }
}

- (void)resume
{
    [_audioQueue resume];
    [self mutexSignal];
}

- (void)pause
{
    if (self.isPlayingOrWaiting && self.status != ZJAudioPlayerStatusFlushing) {
        _pauseRequired = YES;
    }
}

- (void)stop
{
    _stopRequired = YES;
    [self mutexSignal];
}

@end
