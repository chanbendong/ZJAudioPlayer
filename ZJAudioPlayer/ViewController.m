//
//  ViewController.m
//  ZJAudioPlayer
//
//  Created by 吴孜健 on 2018/3/5.
//  Copyright © 2018年 吴孜健. All rights reserved.
//

#import "ViewController.h"
#import "ZJAudioPlayer.h"
@interface ViewController ()

@property (nonatomic, strong) ZJAudioPlayer *player;
@property (weak, nonatomic) IBOutlet UIButton *playOrPauseBtn;
@property (weak, nonatomic) IBOutlet UISlider *slider;
@property (nonatomic, strong) CADisplayLink *displayLink;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!_player) {
        NSString *path = [[NSBundle mainBundle]pathForResource:@"wula" ofType:@"mp3"];
        _player = [[ZJAudioPlayer alloc]initWithFilePath:path fileType:kAudioFileMP3Type];
        
        [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    }
    [_player play];
}


#pragma mark - kvo
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if (object == _player) {
        if ([keyPath isEqualToString:@"status"]) {
            [self performSelectorOnMainThread:@selector(handleStatusChange) withObject:nil waitUntilDone:NO];
        }
    }
}

- (void)handleStatusChange
{
    if (_player.isPlayingOrWaiting) {
        [self.playOrPauseBtn setTitle:@"pause" forState:UIControlStateNormal];
        [self startTimer];
    }else{
        [self.playOrPauseBtn setTitle:@"play" forState:UIControlStateNormal];
        [self stopTimer];
        [self progressMove];
    }
}

#pragma mark - timer
- (void)startTimer
{
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(progressMove)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink.paused = NO;
    
}

- (void)stopTimer
{
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
}





- (void)progressMove
{
    if (!self.slider.tracking) {
        if (_player.duration != 0) {
            self.slider.value = _player.progress/_player.duration;
        }else{
            self.slider.value = 0;
        }
    }
}

#pragma mark - action
- (IBAction)stop:(id)sender {
    [_player stop];
}
- (IBAction)playOrPause:(id)sender {
    if (_player.isPlayingOrWaiting) {
        [_player pause];
    }else{
        [_player play];
    }
}
- (IBAction)seek:(id)sender {
    _player.progress  = _player.duration *self.slider.value;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
