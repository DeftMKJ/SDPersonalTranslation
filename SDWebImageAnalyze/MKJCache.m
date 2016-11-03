//
//  MKJCache.m
//  SDWebImageAnalyze
//
//  Created by MKJING on 16/10/21.
//  Copyright © 2016年 MKJING. All rights reserved.
//

#import "MKJCache.h"

@interface MKJCache ()

@property (nonatomic,strong) NSCache *memeryCache;

@end

@implementation MKJCache


+ (id)shareCCache
{
    static dispatch_once_t onceToken;
    static MKJCache *mkjCache;
    dispatch_once(&onceToken, ^{
        mkjCache = [[MKJCache alloc] init];
    });
    return mkjCache;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _memeryCache = [[NSCache alloc] init];
    }
    return self;
}


- (void)storeValue:(NSNumber *)number forKey:(NSString *)key
{
    [self.memeryCache setObject:number forKey:key];
}

- (NSNumber *)queryValueForKey:(NSString *)key
{
    return [self.memeryCache objectForKey:key];
}
@end
