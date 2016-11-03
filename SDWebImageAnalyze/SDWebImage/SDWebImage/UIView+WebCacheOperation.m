/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCacheOperation.h"
#import "objc/runtime.h"

static char loadOperationKey;

@implementation UIView (WebCacheOperation)

// 拿出operations字典
- (NSMutableDictionary *)operationDictionary {
    NSMutableDictionary *operations = objc_getAssociatedObject(self, &loadOperationKey);
    if (operations) {
        return operations;
    }
    operations = [NSMutableDictionary dictionary];
    objc_setAssociatedObject(self, &loadOperationKey, operations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return operations;
}

// key value的形式添加进operations字典
- (void)sd_setImageLoadOperation:(id)operation forKey:(NSString *)key {
    [self sd_cancelImageLoadOperationWithKey:key];
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    [operationDictionary setObject:operation forKey:key];
}
// 取消之前的下载操作
- (void)sd_cancelImageLoadOperationWithKey:(NSString *)key {
    // Cancel in progress downloader from queue
    //利用AssociatedObject维护的字典，用于存放当前任务中的operation(图片请求)
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    //key为"UIImageViewImageLoad"
    id operations = [operationDictionary objectForKey:key];
    // 当前有正在执行的operation，需要取消任务
    if (operations) {
        //多个operation的是gif(多帧)，单个的是普通图片
        if ([operations isKindOfClass:[NSArray class]]) {
            for (id <SDWebImageOperation> operation in operations) {
                if (operation) {
                    [operation cancel];
                }
            }
        } else if ([operations conformsToProtocol:@protocol(SDWebImageOperation)]){
            [(id<SDWebImageOperation>) operations cancel];
        }
        //删除对应key的对象
        //每次对应UIView有一个图片请求的任务时，都会设置对应的key，所以可以根据这个key来判断是否有正在执行的任务
        [operationDictionary removeObjectForKey:key];
    }
}

- (void)sd_removeImageLoadOperationWithKey:(NSString *)key {
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    [operationDictionary removeObjectForKey:key];
}

@end
