//
//  ZJAudioFileStream.m
//  AudioStream
//
//  Created by 吴孜健 on 2018/2/23.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import "ZJAudioFileStream.h"

#define  BitRateEstimationMaxPackets 5000
#define  BitRateEstimationMinPackets 10

@interface ZJAudioFileStream()
{
    @private
    BOOL _discontinuous;
    AudioFileStreamID _audioFileStreamID;
    
    SInt64 _dataOffset;
    NSTimeInterval _packetDuration;
    
    UInt64 _processedPacketsCount;
    UInt64 _processedPacketsSizeTotal;
    
}
- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID;
- (void)handleAudioFileStreamPackets:(const void *)packets numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescription:(AudioStreamPacketDescription *)packetDescriptions;

@end

#pragma mark - static callbacks
static void ZJAudioFileStreamPropertyListener(void *inClientData,AudioFileStreamID inAudioFileStream, AudioFileStreamPropertyID inPropertyID, UInt32 *inFlags)
{
    ZJAudioFileStream *audioFileStream = (__bridge ZJAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamProperty:inPropertyID];
    
}

static void ZJAudioFileStreamPacketCallBack(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets, const void *inInputData, AudioStreamPacketDescription *inPacketDescrrptions)
{
    ZJAudioFileStream *audioFileStream = (__bridge ZJAudioFileStream *)inClientData;
    [audioFileStream handleAudioFileStreamPackets:inInputData numberOfBytes:inNumberBytes numberOfPackets:inNumberPackets packetDescription:inPacketDescrrptions];
}

@implementation ZJAudioFileStream

#pragma mark - init &dealloc
- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error
{
    if (self = [super init]) {
        _discontinuous = NO;
        _fileType = fileType;
        _fileSize = fileSize;
        [self _openAudioFileStreamWithFileTypeHint:fileType error:error];
    }
    return self;
}

- (void)dealloc
{
    [self _closeAudioFileStream];
}

- (void)_errorForOSStatus:(OSStatus)status error:(NSError *__autoreleasing *)outError
{
    if (status != noErr && outError != NULL) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    }
}

#pragma mark - open & close
- (BOOL)_openAudioFileStreamWithFileTypeHint:(AudioFileTypeID)fileTypeHint error:(NSError *__autoreleasing *)error
{
    OSStatus status = AudioFileStreamOpen((__bridge void *)self, ZJAudioFileStreamPropertyListener, ZJAudioFileStreamPacketCallBack, fileTypeHint, &_audioFileStreamID);
    if (status != noErr) {
        _audioFileStreamID = NULL;
    }
    [self _errorForOSStatus:status error:error];
    return status == noErr;
}

- (void)_closeAudioFileStream
{
    if (self.available) {
        AudioFileStreamClose(_audioFileStreamID);
        _audioFileStreamID = NULL;
    }
}

- (void)close
{
    [self _closeAudioFileStream];
}

- (BOOL)available
{
    return _audioFileStreamID != NULL;
}

#pragma mark - actions
- (NSData *)fetchMagicCookie
{
    UInt32 cookieSize;
    Boolean writable;
    OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (status != noErr) {
        return nil;
    }
    
    void *cookieData = malloc(cookieSize);
    status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (status != noErr) {
        return nil;
    }
    NSData *cookie = [NSData dataWithBytes:cookieData length:cookieSize];
    free(cookieData);
    
    return cookie;
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error
{
    if (self.readyToProducePackets && _packetDuration == 0) {
        [self _errorForOSStatus:-1 error:error];
        return NO;
    }
    
    /**
     解析调用的方法

     param _audioFileStreamID 初始化返回的id
     param inDataByteSize 本次解析的数据长度
     param inData 本次解析的数据
     param inFlags 本次的解析是否和上一次是连续的关系，如果是连续的传入0，否则传入kAudioFileStreamParseFlag_Discontinuity
     return
     */
    OSStatus status = AudioFileStreamParseBytes(_audioFileStreamID, (UInt32)[data length], [data bytes], _discontinuous?kAudioFileStreamParseFlag_Discontinuity:0);
    [self _errorForOSStatus:status error:error];
    return status == noErr;
}


- (SInt64)seekToTime:(NSTimeInterval *)time
{
    SInt64 approximateSeekOffset = _dataOffset+ (*time / _duration)*_audioDataByteCount;
    SInt64 seekToPacket = floor(*time / _packetDuration);
    SInt64 seekByteOffset;
    UInt32 ioFlags = 0;
    SInt64 outDataByteOffset;
    OSStatus status = AudioFileStreamSeek(_audioFileStreamID, seekToPacket, &outDataByteOffset, &ioFlags);
    if (status == noErr && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated)) {
        //如果audioFileStreamSeek找到了准确的帧字节偏移，需要修正一下时间
        *time -= ((approximateSeekOffset-_dataOffset)-outDataByteOffset)*8.0/_bitRate;
        seekByteOffset = outDataByteOffset+_dataOffset;
    }else{
        _discontinuous = YES;
        seekByteOffset = approximateSeekOffset;
    }
    return seekByteOffset;
}

#pragma mark - callbacks
- (void)calculateBitRate
{
    if (_packetDuration && _processedPacketsCount > BitRateEstimationMinPackets && _processedPacketsCount <= BitRateEstimationMaxPackets) {
        double averagePacketByteSize = _processedPacketsSizeTotal / _processedPacketsCount;
        _bitRate = 8.0 * averagePacketByteSize/_packetDuration;
    }
}

- (void)calculateDuration
{
    if (_fileSize > 0  && _bitRate > 0) {
        _duration = ((_fileSize-_dataOffset)*8.0)/_bitRate;
    }
}

- (void)calculatePacketDuration
{
    if (_format.mSampleRate > 0) {
        _packetDuration = _format.mFramesPerPacket / _format.mSampleRate;
    }
}

- (void)handleAudioFileStreamProperty:(AudioFileStreamPropertyID)propertyID
{
    if (propertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        
        _readyToProducePackets = YES;
        _discontinuous = YES;
        
        UInt32 sizeOfUInt32 = sizeof(_maxPacketSize);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &_maxPacketSize);
        
        if (status != noErr || _maxPacketSize == 0) {
            status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_ReadyToProducePackets, &sizeOfUInt32, &_maxPacketSize);
        }
        
        if (_delegate && [_delegate respondsToSelector:@selector(audioFileStreamReadyToProducePackets:)]) {
            [_delegate audioFileStreamReadyToProducePackets:self];
        }
    }else if (propertyID == kAudioFileStreamProperty_DataOffset){
        UInt32 offsetSize = sizeof(_dataOffset);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &_dataOffset);
        [self calculateDuration];
    }else if (propertyID == kAudioFileStreamProperty_DataFormat){
        UInt32 asbdSize = sizeof(_format);
        AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &_format);
        [self calculatePacketDuration];
    }else if (propertyID == kAudioFileStreamProperty_AudioDataByteCount){
//        UInt32 dataOffset;
        UInt32 audioDataByteCount;
        UInt32 byteCountSize = sizeof(audioDataByteCount);
        OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
        _audioDataByteCount = audioDataByteCount;
        if (status == noErr) {
//            NSLog(@"audioDataByteCount : %u, byteCountSize: %u",audioDataByteCount,byteCountSize);
        }
    }
    else if (propertyID == kAudioFileStreamProperty_FormatList){
        Boolean outWriteable;
        UInt32 formatListSize;
        OSStatus status = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
        if (status == noErr) {
            AudioFormatListItem *formatList = malloc(formatListSize);
            OSStatus status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
            if (status == noErr) {
                UInt32 supportedFormatsSize;
                status = AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize);
                if (status != noErr) {
                    free(formatList);
                    return;
                }
                
                UInt32 supportedFormatCount = supportedFormatsSize / sizeof(OSType);
                OSType *supportedFormats = (OSType *)malloc(supportedFormatsSize);
                status = AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs, 0, NULL, &supportedFormatsSize, supportedFormats);
                if (status != noErr) {
                    free(formatList);
                    free(supportedFormats);
                    return;
                }
                
                for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i++) {
                    AudioStreamBasicDescription format = formatList[i].mASBD;
                    for (UInt32 j = 0; j < supportedFormatCount; j++) {
                        if (format.mFormatID == supportedFormats[j]) {
                            _format = format;
                            [self calculatePacketDuration];
                            break;
                        }
                    }
                }
                free(supportedFormats);
            };
            free(formatList);
            
        }
    }
}

- (void)handleAudioFileStreamPackets:(const void *)packets numberOfBytes:(UInt32)numberOfBytes numberOfPackets:(UInt32)numberOfPackets packetDescription:(AudioStreamPacketDescription *)packetDescriptions
{
    if (_discontinuous) {
        _discontinuous = NO;
    }
    
    if (numberOfBytes == 0 || numberOfPackets == 0) {
        return;
    }
    
    BOOL deletePackDesc = NO;
    
    if (packetDescriptions == NULL) {
        deletePackDesc = YES;
        UInt32 packetSize = numberOfBytes / numberOfPackets;
        AudioStreamPacketDescription *descriptions = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription)*numberOfPackets);
        for (int i = 0; i < numberOfPackets; i++) {
            UInt32 packetOffset = packetSize * i;
            descriptions[i].mStartOffset  = packetOffset;
            descriptions[i].mVariableFramesInPacket = 0;
            if (i == numberOfPackets-1) {
                descriptions[i].mDataByteSize = numberOfPackets-packetOffset;
            }else{
                descriptions[i].mDataByteSize = packetSize;
            }
        }
        packetDescriptions = descriptions;
    }
    NSMutableArray *parseDataArray = [NSMutableArray array];
    for (int i = 0; i < numberOfPackets; i++) {
        SInt64 packetOffset = packetDescriptions[i].mStartOffset;
        ZJParseAudioData *parsedData = [ZJParseAudioData parsedAudioDataWithBytes:packets+packetOffset packetDescription:packetDescriptions[i]];
//        NSLog(@"packetdata : %@",parsedData.data);
        [parseDataArray addObject:parsedData];
        
        if (_processedPacketsCount < BitRateEstimationMaxPackets) {
            _processedPacketsSizeTotal += parsedData.packetDescription.mDataByteSize;
            _processedPacketsCount += 1;
            [self calculateBitRate];
            [self calculateDuration];
        }
    }
    
    if (_delegate && [_delegate respondsToSelector:@selector(audioFileStream:audioDataParsed:)]) {
        [_delegate audioFileStream:self audioDataParsed:parseDataArray];
    }
    if (deletePackDesc) {
        free(packetDescriptions);
    }
}

@end
