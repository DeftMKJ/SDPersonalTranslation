//
//  SDWebImageCompat.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 11/12/12.
//  Copyright (c) 2012 Dailymotion. All rights reserved.
//

#import "SDWebImageCompat.h"

#if !__has_feature(objc_arc)
#error SDWebImage is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif


//当使用imageNamed加载图片时, iOS会根据当前设备scale以及图片后缀计算出size和scale
//
//例如对于120*120pixel的图片来说, 在设备phone6(scale=2)上加载图片时
//
//图片名没有@2x, @3x后缀, size = {60, 60}, scale = 2.0
//
//图片名的后缀为@2x, size = {60, 60}, scale = 2.0
//
//图片名的后缀为@3x, size = {40, 40}, scale = 3.0
//
//而从网络下载的图片, size和pixel是一一对应的, 即1 size = 1 pixel
//
//例如对于上述120*120pixel的图片来说
//
//size = {120, 120}, scale = 1.0
//对于@2x, @3x的图片来说, 此时的size和scale是不正确的
//
//所以SDScaledImageForKey就是将size和scale更新成与图片名后缀一致

//缩放操作可以查看SDWebImageCompat文件中的SDScaledImageForKey函数

inline UIImage *SDScaledImageForKey(NSString *key, UIImage *image) {
    if (!image) {
        return nil;
    }
    
    if ([image.images count] > 0) {
        NSMutableArray *scaledImages = [NSMutableArray array];

        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:SDScaledImageForKey(key, tempImage)];
        }

        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
            CGFloat scale = 1;
            if (key.length >= 8) {
                NSRange range = [key rangeOfString:@"@2x."];
                if (range.location != NSNotFound) {
                    scale = 2.0;
                }
                
                range = [key rangeOfString:@"@3x."];
                if (range.location != NSNotFound) {
                    scale = 3.0;
                }
            }

            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
            image = scaledImage;
        }
        return image;
    }
}

NSString *const SDWebImageErrorDomain = @"SDWebImageErrorDomain";
