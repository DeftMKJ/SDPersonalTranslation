//
//  MKJCache.h
//  SDWebImageAnalyze
//
//  Created by MKJING on 16/10/21.
//  Copyright © 2016年 MKJING. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MKJCache : NSObject

+ (id)shareCCache;

- (void)storeValue:(NSNumber *)number forKey:(NSString *)key;

- (NSNumber *)queryValueForKey:(NSString *)key;

@end
