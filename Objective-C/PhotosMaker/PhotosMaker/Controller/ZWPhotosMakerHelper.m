//
//  ZWPhotosMakerHelper.m
//  ZWMusicPlayer
//
//  Created by Darsky on 2018/1/27.
//  Copyright © 2018年 Darsky. All rights reserved.
//

#import "ZWPhotosMakerHelper.h"
#import <AVFoundation/AVFoundation.h>
#import "ZWPhotosMakerAssetModel.h"
#import "ZWPhotosNodeModel.h"


#define videoFrame 1
#define frameSize   3


@interface ZWPhotosMakerHelper()
{
}
@property (copy, nonatomic) NSString *videoPath;
@property (strong, nonatomic) AVAssetWriter *videoWriter;
@property (strong, nonatomic) AVAssetWriterInput *videoWriterInput;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property (nonatomic) CGSize videoSize;

@property (strong, nonatomic) NSMutableArray *defaultMusicArray;

@end


@implementation ZWPhotosMakerHelper


- (BOOL)setupVideoWriter {

    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    self.videoPath = [documents stringByAppendingPathComponent:@"video.mp4"];
    
    [[NSFileManager defaultManager] removeItemAtPath:self.videoPath
                                               error:nil];
    
    NSError *error;
    
    // Configure videoWriter
    NSURL *fileUrl = [NSURL fileURLWithPath:self.videoPath];
    self.videoWriter = [[AVAssetWriter alloc] initWithURL:fileUrl fileType:AVFileTypeMPEG4 error:&error];
    NSParameterAssert(self.videoWriter);
    
    // Configure videoWriterInput
    NSDictionary *videoCompressionProps = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:_videoSize.width * _videoSize.height], AVVideoAverageBitRateKey, nil];
    
    NSDictionary *videoSettings = @{AVVideoCodecKey: AVVideoCodecH264,
                                    AVVideoWidthKey: @(_videoSize.width),
                                    AVVideoHeightKey: @(_videoSize.height),
                                    AVVideoCompressionPropertiesKey: videoCompressionProps};
    
    self.videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                               outputSettings:videoSettings];
    
    NSParameterAssert(self.videoWriterInput);
    self.videoWriterInput.expectsMediaDataInRealTime = YES;
    NSDictionary *bufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey, nil];
    
    self.adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.videoWriterInput
                                                                                    sourcePixelBufferAttributes:bufferAttributes];
    
    // add input
    [self.videoWriter addInput:self.videoWriterInput];
    [self.videoWriter startWriting];
    [self.videoWriter startSessionAtSourceTime:kCMTimeZero];
    
    return YES;
}

- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    CVPixelBufferRef pxbuffer = NULL;
    CGFloat frameWidth = CGImageGetWidth(image);
    CGFloat frameHeight = CGImageGetHeight(image);
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, frameWidth,
                                          frameHeight, kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, frameWidth,
                                                 frameHeight, 8, CVPixelBufferGetBytesPerRow(pxbuffer), rgbColorSpace,
                                                 kCGImageAlphaPremultipliedFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformIdentity);
    CGContextDrawImage(context, CGRectMake(0, 0, frameWidth,
                                           frameHeight), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

-(NSMutableArray *)praseGIFDataToImageArray:(NSData *)data;
{
    NSMutableArray *frames = [[NSMutableArray alloc] init];
    CGImageSourceRef src = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    CGFloat animationTime = 0.f;
    if (src) {
        size_t l = CGImageSourceGetCount(src);
        frames = [NSMutableArray arrayWithCapacity:l];
        for (size_t i = 0; i < l; i++) {
            CGImageRef img = CGImageSourceCreateImageAtIndex(src, i, NULL);
            NSDictionary *properties = (NSDictionary *)CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, i, NULL));
            NSDictionary *frameProperties = [properties objectForKey:(NSString *)kCGImagePropertyGIFDictionary];
            NSNumber *delayTime = [frameProperties objectForKey:(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
            animationTime += [delayTime floatValue];
            if (img) {
                [frames addObject:[UIImage imageWithCGImage:img]];
                CGImageRelease(img);
            }
        }
        CFRelease(src);
    }
    return frames;
}


- (void)startMakePhotoVideosWithAnimationGroup:(CAAnimationGroup*)group
                                     withNodes:(NSArray*)nodeArray
                                   withBgImage:(UIImage*)bgImage
                                      andMusic:(MusicFileModel*)musicModel
                                       forSize:(CGSize)videoSize
                               withFinishBlock:(PhotosMakeFinishBlock)photosMakeFinishBlock
                              andProgressBlock:(PhotosMakeProgressBlock)progressBlock
                              adnErrorMsgBlock:(ErrorMsgBlock)errorMsgBlock
{
    self.videoSize = videoSize;
    self.finishBlock = photosMakeFinishBlock;
    self.progressBlock = progressBlock;
    self.errorMsgBlock = errorMsgBlock;
    if (self.videoWriter == nil && [self setupVideoWriter])
    {
        dispatch_queue_t dispatchQueue = dispatch_queue_create("mediaInputQueue", NULL);
        int __block frame = 0;
        
        float duration = group.duration;
        UIImage *emptyImage = [self createImageWithColor:[UIColor whiteColor]];
        CVPixelBufferRef buffer = [self pixelBufferFromCGImage:emptyImage.CGImage];
        [self.videoWriterInput requestMediaDataWhenReadyOnQueue:dispatchQueue
                                                     usingBlock:^
         {
             while ([self.videoWriterInput isReadyForMoreMediaData])
             {
                 if(![self.adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(frame, (int32_t)1)])
                 {
                     NSError *error = self.videoWriter.error;
                     if(error)
                     {
                         NSLog(@"Unresolved error %@,%@.", error, [error userInfo]);
                         if (self.errorMsgBlock != nil)
                         {
                             self.errorMsgBlock([error localizedDescription]);
                             CVPixelBufferRelease(buffer);
                             break;
                         }
                     }
                 }
                 if(++frame >= (int)duration)
                 {
                     CVPixelBufferRelease(buffer);
                     [self.videoWriterInput markAsFinished];
                     [self.videoWriter finishWritingWithCompletionHandler:^{
                         [self createPhotoVideosWithAnimationGroup:group
                                                     withVideoNode:nodeArray
                                                       withBgImage:bgImage
                                                          andMusic:musicModel];
                         self.adaptor = nil;
                         self.videoWriterInput = nil;
                         self.videoWriter = nil;
                     }];
                     break;
                 }
             }
         }];
    }
}

- (void)createPhotoVideosWithAnimationGroup:(CAAnimationGroup*)group
                              withVideoNode:(NSArray*)videoArray
                                withBgImage:(UIImage*)bgImage
                                   andMusic:(MusicFileModel*)musicModel;
{
    AVMutableComposition *avMutableComposition = [AVMutableComposition composition];
    AVMutableCompositionTrack *avMutableCompositionTrack = [avMutableComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                             preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *auMutableCompositionTrack = [avMutableComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                             preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableVideoComposition *avMutableVideoComposition = [AVMutableVideoComposition videoComposition];
    avMutableVideoComposition.renderSize = _videoSize;
    avMutableVideoComposition.renderScale = 1.0;
    avMutableVideoComposition.frameDuration = CMTimeMake(1, 30);
    AVAsset *avAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:self.videoPath]];
    CMTime assetTime = [avAsset duration];
    Float64 duration = CMTimeGetSeconds(assetTime);
    AVAssetTrack *avAssetTrack = nil;
    NSError *error = nil;
    CMTime currentDuration = avMutableComposition.duration;
    avAssetTrack = [[avAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    
    if ([avMutableCompositionTrack insertTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, 24),
                                                                   CMTimeMakeWithSeconds(duration, 24))
                                           ofTrack:avAssetTrack
                                            atTime:currentDuration
                                             error:&error])
    {
        CALayer *parentLayer = [CALayer layer];
        CALayer *videoLayer = [CALayer layer];
        parentLayer.frame = CGRectMake(0, 0, _videoSize.width, _videoSize.height);
        videoLayer.frame = CGRectMake(0, 0, _videoSize.width, _videoSize.height);
        [parentLayer setBackgroundColor:[UIColor colorWithPatternImage:bgImage].CGColor];
        [parentLayer addSublayer:videoLayer];
        
        //插入音频
        NSString *audioPath =[ [NSBundle mainBundle]  pathForResource:musicModel.fileName
                                                               ofType:@"mp3"];
        AVAsset *auAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:audioPath]];
        
        CMTime auAssetTime = [auAsset duration];
        Float64 audioDuration = CMTimeGetSeconds(auAssetTime);
        
        AVAssetTrack *auAssetTrack = nil;
        auAssetTrack = [[auAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        if ( [auMutableCompositionTrack insertTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, videoFrame),
                                                                        CMTimeMakeWithSeconds(duration+3, videoFrame))
                                                ofTrack:auAssetTrack
                                                 atTime:kCMTimeZero
                                                  error:&error])
        {
            //            auMutableCompositionTrack.preferredTransform = auAssetTrack.preferredTransform;
        }
        
        group.beginTime = AVCoreAnimationBeginTimeAtZero;
        [videoLayer addAnimation:group forKey:nil];
        
        
        avMutableVideoComposition.animationTool = [AVVideoCompositionCoreAnimationTool
                                                   videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer
                                                   inLayer:parentLayer];
        
        AVMutableVideoCompositionInstruction *avMutableVideoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        
        [avMutableVideoCompositionInstruction setTimeRange:CMTimeRangeMake(kCMTimeZero, [avMutableComposition duration])];
        
        AVMutableVideoCompositionLayerInstruction *avMutableVideoCompositionLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:avMutableCompositionTrack];
        [avMutableVideoCompositionLayerInstruction setTransform:avMutableCompositionTrack.preferredTransform
                                                         atTime:kCMTimeZero];
        
        avMutableVideoCompositionInstruction.layerInstructions = [NSArray arrayWithObject:avMutableVideoCompositionLayerInstruction];
        avMutableVideoComposition.instructions = [NSArray arrayWithObject:avMutableVideoCompositionInstruction];
        
        
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL* saveLocationURL = [[NSURL alloc] initFileURLWithPath:[NSString stringWithFormat:@"%@/result.mp4", documents]];
        if ([fileManager fileExistsAtPath:saveLocationURL.relativePath])
        {
            [fileManager removeItemAtURL:saveLocationURL
                                   error:nil];
        }
        __weak CAAnimationGroup *weakgroup = group;
        __block AVMutableComposition *targetMutableComposition = avMutableComposition;
        
        AVAssetExportSession *avAssetExportSession = [[AVAssetExportSession alloc] initWithAsset:avMutableComposition
                                                                                      presetName:AVAssetExportPresetHighestQuality];
        [avAssetExportSession setVideoComposition:avMutableVideoComposition];
        [avAssetExportSession setOutputURL:saveLocationURL];
        [avAssetExportSession setOutputFileType:AVFileTypeMPEG4];
        [avAssetExportSession setShouldOptimizeForNetworkUse:NO];
        [avAssetExportSession exportAsynchronouslyWithCompletionHandler:^(void)
         {
             switch (avAssetExportSession.status)
             {
                 case AVAssetExportSessionStatusExporting:
                 {
                     if (self.progressBlock != nil)
                     {
                         self.progressBlock(avAssetExportSession.progress);
                     }
                 }
                     break;
                 case AVAssetExportSessionStatusFailed:
                 {
                     NSLog(@"exporting failed %@",[avAssetExportSession error]);
                     if (self.errorMsgBlock != nil)
                     {
                         self.errorMsgBlock([[avAssetExportSession error] localizedDescription]);
                     }
                 }
                     break;
                 case AVAssetExportSessionStatusCompleted:
                 {
                     NSLog(@"生成原动画视频");
                     // 想做什么事情在这个
                     weakgroup.animations = nil;
                     targetMutableComposition = nil;
                     [self mixVideoForOrigin:saveLocationURL
                                   WithNodes:videoArray];
                 }
                     break;
                 case AVAssetExportSessionStatusCancelled:
                 {
                     NSLog(@"export cancelled");
                     if (self.errorMsgBlock != nil)
                     {
                         self.errorMsgBlock(@"export cancelled");
                     }
                 }
                     break;
                 default:
                     break;
             }
         }];
    }
}

- (void)mixVideoForOrigin:(NSURL*)originVideoUrl
                WithNodes:(NSArray*)nodeArray
{
    AVMutableComposition *resultComposition = [AVMutableComposition composition];
    AVMutableCompositionTrack * videoMutableCompositionTrack = nil;//视频合成轨道
    videoMutableCompositionTrack = [resultComposition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                            preferredTrackID:kCMPersistentTrackID_Invalid];
    
    AVMutableCompositionTrack *audioMutableCompositionTrack = nil;//音频合成轨道
    audioMutableCompositionTrack = [resultComposition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                                             preferredTrackID:kCMPersistentTrackID_Invalid];
    
    
    //原视频 asset
    AVAsset *originAsset   = [AVAsset assetWithURL:originVideoUrl];
    CMTime originAssetTime = [originAsset duration];
    Float64 originAssetDuration = CMTimeGetSeconds(originAssetTime);
    AVAssetTrack *oriVideoAssetTrack = [[originAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    AVAssetTrack *oriAudioAssetTrack = [[originAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    CALayer *videoLayer = [CALayer layer];
    videoLayer.frame = CGRectMake(0, 0, _videoSize.width, _videoSize.height);
    

    AVMutableVideoCompositionLayerInstruction *avMutableVideoCompositionLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoMutableCompositionTrack];
    
    NSMutableArray *instructions = [NSMutableArray array];
    NSError *error;
    for (int x = 0; x<nodeArray.count; x++)
    {
        ZWPhotosNodeModel *nodeModel = nodeArray[x];
        
        if (nodeModel.type == ZWPhotosNodeTypeVideo)
        {
            AVAsset *insertAsset = nodeModel.object;
            AVAssetTrack *insertAssetTrack = [[insertAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
            [videoMutableCompositionTrack insertTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, videoFrame),
                                                CMTimeMakeWithSeconds(nodeModel.duration, videoFrame))
                                                  ofTrack:insertAssetTrack
                                                   atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)
                                                    error:&error];


            float scale = 1.0;

            if (nodeModel.isPortraitVideo)
            {
                if (nodeModel.degree == 0)//不含转角的竖视频
                {
                    scale = _videoSize.height/nodeModel.mediaHeight;
                    CGAffineTransform trans = CGAffineTransformMakeScale(scale, scale);
                    
                    trans = CGAffineTransformTranslate(trans,((float)_videoSize.width/scale/2.0- nodeModel.mediaWidth/2.0),0);
                    
                    
                    [avMutableVideoCompositionLayerInstruction setTransform:trans
                                                                     atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)];
                }
                else
                {
                    scale = _videoSize.height/nodeModel.mediaWidth;
                    CGAffineTransform trans = CGAffineTransformMakeScale(scale, scale);
                    trans = CGAffineTransformRotate(trans, M_PI_2);
                    
                    trans = CGAffineTransformTranslate(trans, 0, -((float)_videoSize.width/scale/2.0+ nodeModel.mediaHeight/2.0));
                    
                    
                    [avMutableVideoCompositionLayerInstruction setTransform:trans
                                                                     atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)];
                }
            }
            else
            {
                scale = _videoSize.width/nodeModel.mediaWidth;
                CGAffineTransform trans = CGAffineTransformMake(insertAssetTrack.preferredTransform.a*scale, insertAssetTrack.preferredTransform.b*scale, insertAssetTrack.preferredTransform.c*scale, insertAssetTrack.preferredTransform.d*scale, insertAssetTrack.preferredTransform.tx*scale, insertAssetTrack.preferredTransform.ty*scale);

                [avMutableVideoCompositionLayerInstruction setTransform:trans
                                                                 atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)];
            }
//
//            [avMutableVideoCompositionLayerInstruction setTransform:insertTransform
//                                                             atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)];
            
        }
        else
        {
            [videoMutableCompositionTrack insertTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame),
                                                                       CMTimeMakeWithSeconds(nodeModel.duration, videoFrame))
                                                  ofTrack:oriVideoAssetTrack
                                                   atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)
                                                    error:&error];


            [avMutableVideoCompositionLayerInstruction setTransform:oriVideoAssetTrack.preferredTransform
                                                             atTime:CMTimeMakeWithSeconds(nodeModel.startTime, videoFrame)];
        }
    }
    [instructions addObject:avMutableVideoCompositionLayerInstruction];
    
    //插入音频
    if ( [audioMutableCompositionTrack insertTimeRange:CMTimeRangeMake(CMTimeMakeWithSeconds(0, videoFrame),
                                                                    CMTimeMakeWithSeconds(originAssetDuration, videoFrame))
                                            ofTrack:oriAudioAssetTrack
                                             atTime:kCMTimeZero
                                              error:&error])
    {
        //            auMutableCompositionTrack.preferredTransform = auAssetTrack.preferredTransform;
    }
    
    AVMutableVideoCompositionInstruction *avMutableVideoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    
    [avMutableVideoCompositionInstruction setTimeRange:CMTimeRangeMake(kCMTimeZero, [resultComposition duration])];
    

    avMutableVideoCompositionInstruction.layerInstructions = instructions;
    
    
    //插入视频处理
    AVMutableVideoComposition *avMutableVideoComposition = [AVMutableVideoComposition videoComposition];
    avMutableVideoComposition.renderSize = _videoSize;
    avMutableVideoComposition.frameDuration = CMTimeMake(1, 30);
    //avMutableVideoComposition.instructions = instructions;
    avMutableVideoComposition.instructions = [NSArray arrayWithObject:avMutableVideoCompositionInstruction];



    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL* saveLocationURL = [[NSURL alloc] initFileURLWithPath:[NSString stringWithFormat:@"%@/mixResult.mp4", documents]];
    if ([fileManager fileExistsAtPath:saveLocationURL.relativePath])
    {
        [fileManager removeItemAtURL:saveLocationURL
                               error:nil];
    }
    
    AVAssetExportSession *avAssetExportSession = [[AVAssetExportSession alloc] initWithAsset:resultComposition
                                                                                  presetName:AVAssetExportPresetHighestQuality];
    [avAssetExportSession setVideoComposition:avMutableVideoComposition];
    [avAssetExportSession setOutputURL:saveLocationURL];
    [avAssetExportSession setOutputFileType:AVFileTypeMPEG4];
    [avAssetExportSession setShouldOptimizeForNetworkUse:NO];
    [avAssetExportSession exportAsynchronouslyWithCompletionHandler:^(void)
     {
         switch (avAssetExportSession.status)
         {
             case AVAssetExportSessionStatusExporting:
             {
                 if (self.progressBlock != nil)
                 {
                     self.progressBlock(avAssetExportSession.progress);
                 }
             }
                 break;
             case AVAssetExportSessionStatusFailed:
             {
                 NSLog(@"exporting failed %@",[avAssetExportSession error]);
                 if (self.errorMsgBlock != nil)
                 {
                     self.errorMsgBlock([[avAssetExportSession error] localizedDescription]);
                 }
             }
                 break;
             case AVAssetExportSessionStatusCompleted:
             {
                 NSLog(@"exporting completed");
                 // 想做什么事情在这个
                 [fileManager removeItemAtURL:originVideoUrl
                                        error:nil];
                 if (self.finishBlock != nil)
                 {
                     self.finishBlock(saveLocationURL);
                 }
             }
                 break;
             case AVAssetExportSessionStatusCancelled:
             {
                 NSLog(@"export cancelled");
                 if (self.errorMsgBlock != nil)
                 {
                     self.errorMsgBlock(@"export cancelled");
                 }
             }
                 break;
             default:
                 break;
         }
     }];
}


- (UIImage*)createImageWithColor:(UIColor*)color
{
    CGRect rect=CGRectMake(0.0f, 0.0f, self.videoSize.width, self.videoSize.height);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextFillRect(context, rect);
    UIImage *theImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return theImage;
}

- (void)dealloc
{
    if (self.videoWriter)
    {
        self.adaptor = nil;
        self.videoWriterInput = nil;
        self.videoWriter = nil;
    }
    self.finishBlock = nil;
    self.errorMsgBlock = nil;
}

- (void)initializeMusicFolderWithSuccessBlock:(void(^)(NSArray* array))successBlock
                                andErrorBlock:(void(^)(NSError *error))errorBlock
{
    NSArray *defaultMusicArray  = @[@"MKJ - Time",@"Matteo - Panama",@"Sam Tsui,Alex G - Don't Wanna Know／We Don't Talk Anymore",@"AnimeVibe - Умри если меня не любишь",@"Saphire - Be Good"];
    NSMutableArray *resultArray = [NSMutableArray array];
    for (int x = 0; x<defaultMusicArray.count; x++)
    {
        MusicFileModel *musicModel = [[MusicFileModel alloc] init];
        musicModel.fileName = defaultMusicArray[x];
        NSString *path =[ [NSBundle mainBundle]  pathForResource:musicModel.fileName
                                                          ofType:@"mp3"];
        AVURLAsset *avURLAsset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:path]
                                                         options:nil];
        musicModel.duration = avURLAsset.duration.value/avURLAsset.duration.timescale;
        for (NSString *format in [avURLAsset availableMetadataFormats])
        {
            for (AVMetadataItem *metaData in [avURLAsset metadataForFormat:format])
            {
                NSLog(@"%@",metaData.commonKey);
                if ([metaData.commonKey isEqualToString:@"title"])
                {
                    musicModel.musicName = (NSString*)metaData.value;
                }
                else if ([metaData.commonKey isEqualToString:@"artwork"])
                {
                    musicModel.coverImage = [UIImage imageWithData:(NSData*)metaData.value];
                }
                else if ([metaData.commonKey isEqualToString:@"artist"])
                {
                    musicModel.artist = (NSString*)metaData.value;
                }
            }
        }
        [resultArray addObject:musicModel];
    }
    if (resultArray.count > 0)
    {
        successBlock(resultArray);
    }
    else
    {
        errorBlock(nil);
    }
}


@end
