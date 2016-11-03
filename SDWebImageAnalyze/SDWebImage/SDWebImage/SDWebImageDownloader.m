/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

@interface SDWebImageDownloader () <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (strong, nonatomic) NSOperationQueue *downloadQueue; // 所有的下载放到队列里面
@property (weak, nonatomic) NSOperation *lastAddedOperation;
@property (assign, nonatomic) Class operationClass;
//  结构{"url":[{"progress":"progressBlock"},{"complete":"completeBlock"}]}
@property (strong, nonatomic) NSMutableDictionary *URLCallbacks;//!< 图片下载的这些回调信息存储在这里
@property (strong, nonatomic) NSMutableDictionary *HTTPHeaders;
// This queue is used to serialize the handling of the network responses of all the download operation in a single queue
// 所有下载操作的网络响应序列化处理是放在一个自定义的并行调度队列中来处理的
// _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t barrierQueue;
//更新：关于GCD，还有两个需要说的：

//func dispatch_barrier_async(_ queue: dispatch_queue_t, _ block: dispatch_block_t):
//这个方法重点是你传入的 queue，当你传入的 queue 是通过 DISPATCH_QUEUE_CONCURRENT 参数自己创建的 queue 时，这个方法会阻塞这个 queue（注意是阻塞 queue ，而不是阻塞当前线程），一直等到这个 queue 中排在它前面的任务都执行完成后才会开始执行自己，自己执行完毕后，再会取消阻塞，使这个 queue 中排在它后面的任务继续执行。
//如果你传入的是其他的 queue, 那么它就和 dispatch_async 一样了。
//func dispatch_barrier_sync(_ queue: dispatch_queue_t, _ block: dispatch_block_t):
//这个方法的使用和上一个一样，传入 自定义的并发队列（DISPATCH_QUEUE_CONCURRENT），它和上一个方法一样的阻塞 queue，不同的是 这个方法还会 阻塞当前线程。
//如果你传入的是其他的 queue, 那么它就和 dispatch_sync 一样了。


// The session in which data tasks will run
@property (strong, nonatomic) NSURLSession *session;

@end

@implementation SDWebImageDownloader

+ (void)initialize {
    // Bind SDNetworkActivityIndicator if available (download it here: http://github.com/rs/SDNetworkActivityIndicator )
    // To use it, just add #import "SDNetworkActivityIndicator.h" in addition to the SDWebImage import
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop

        // Remove observer in case it was previously added.
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}

+ (SDWebImageDownloader *)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        _operationClass = [SDWebImageDownloaderOperation class];
        _shouldDecompressImages = YES;
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder;
        _downloadQueue = [NSOperationQueue new];
        _downloadQueue.maxConcurrentOperationCount = 6;
        _downloadQueue.name = @"com.hackemist.SDWebImageDownloader";
        _URLCallbacks = [NSMutableDictionary new];
#ifdef SD_WEBP
        _HTTPHeaders = [@{@"Accept": @"image/webp,image/*;q=0.8"} mutableCopy];
#else
        _HTTPHeaders = [@{@"Accept": @"image/*;q=0.8"} mutableCopy];
#endif
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        _downloadTimeout = 15.0;

        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sessionConfig.timeoutIntervalForRequest = _downloadTimeout;

        /**
         *  Create the session for this task
         *  We send nil as delegate queue so that the session creates a serial operation queue for performing all delegate
         *  method calls and completion handler calls.
         */
        self.session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                     delegate:self
                                                delegateQueue:nil];
    }
    return self;
}

- (void)dealloc {
    [self.session invalidateAndCancel];
    self.session = nil;

    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value) {
        self.HTTPHeaders[field] = value;
    }
    else {
        [self.HTTPHeaders removeObjectForKey:field];
    }
}

- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    return self.HTTPHeaders[field];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}

- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}

- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}

- (void)setOperationClass:(Class)operationClass {
    _operationClass = operationClass ?: [SDWebImageDownloaderOperation class];
}

// Downloader开启下载图片模式
// SDWebImageDownloader  异步下载器，并对图像进行了优化处理
- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageDownloaderCompletedBlock)completedBlock {
    __block SDWebImageDownloaderOperation *operation;
    __weak __typeof(self)wself = self;

    // 290行，同一个方法里面，进行urlCallBacks的组装
    // 该方法有点明白了，就是让同一个url值生成一个createCallBack -->也就是只出来一个operation任务
    // wself.downloadQueue同一url只会加入一次，但是多次重复请求，urlcallbacks的url数组里面会有多个回调block，这个不影响，只要正真下载一次就好了，回调可以遍历，下面下载完都一直在遍历，没错，这就对了
    [self addProgressCallback:progressBlock completedBlock:completedBlock forURL:url createCallback:^{
        NSTimeInterval timeoutInterval = wself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }

        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        // 防止NSURLCache 和 SDImageCache重复缓存 如果没有明确告知需要缓存，则禁用图片请求的缓存操作
         // 1. 创建请求对象，并根据options参数设置其属性
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        // 设置http头部
        if (wself.headersFilter) {
            request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = wself.HTTPHeaders;
        }
        //SDWebImageDownloaderOperation派生自NSOperation，负责图片下载工作
        // 2. 创建SDWebImageDownloaderOperation操作对象，并进行配置
        // SDWebImageDownloaderOperation class
        operation = [[wself.operationClass alloc] initWithRequest:request
                                                        inSession:self.session
                                                          options:options
                                                         progress:^(NSInteger receivedSize, NSInteger expectedSize) {
                                                             SDWebImageDownloader *sself = wself;
                                                             if (!sself) return;
                                                             __block NSArray *callbacksForURL;
                                                             // 3. 从管理器的callbacksForURL中找出该URL所有的进度处理回调并调用
                                                             // 这个barrierQueue是并发的，如果是get main queue的话就死锁了
                                                             // 我个人感觉去掉直接写也问题不大，不知道为什么这么写？？？反正是顺序执行
                                                             dispatch_sync(sself.barrierQueue, ^{
                                                                 // URLCallbacks是mutale字典对象
                                                                 callbacksForURL = [sself.URLCallbacks[url] copy];
                                                             });
                                                             // 进度正常，肯定有多个block
                                                             for (NSDictionary *callbacks in callbacksForURL) {
                                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                                     SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
                                                                     // 正在下载的时候回传已经收到的size和totalsize出去
                                                                     if (callback) callback(receivedSize, expectedSize);
                                                                 });
                                                             }
                                                         }
                                                        // 下载完之后会进到这个回调，然后我们用之前存起来的回调再回调出去
                                                        completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                                                            SDWebImageDownloader *sself = wself;
                                                            if (!sself) return;
                                                            __block NSArray *callbacksForURL;
                                                            // 4. 从管理器的callbacksForURL中找出该URL所有的完成处理回调并调用，
                                                            // 如果finished为YES，则将该url对应的回调信息从URLCallbacks中删除
                                                            // 个人理解阻塞当前线程，而且barrierQueue也阻塞 那么当同一个URL完成的时候直接没了对象，重复下载也没用了
                                                            dispatch_barrier_sync(sself.barrierQueue, ^{
                                                                callbacksForURL = [sself.URLCallbacks[url] copy];
                                                                if (finished) {
                                                                    [sself.URLCallbacks removeObjectForKey:url];
                                                                }
                                                            });
                                                            // 这里一般只有一个，但是多次重复请求
                                                            for (NSDictionary *callbacks in callbacksForURL) {
                                                                SDWebImageDownloaderCompletedBlock callback = callbacks[kCompletedCallbackKey];
                                                                if (callback) callback(image, data, error, finished);
                                                            }
                                                        }
                                                        cancelled:^{
                                                            SDWebImageDownloader *sself = wself;
                                                            // 5. 取消操作将该url对应的回调信息从URLCallbacks中删除
                                                            // 阻塞barrierqueue
                                                            if (!sself) return;
                                                            dispatch_barrier_async(sself.barrierQueue, ^{
                                                                [sself.URLCallbacks removeObjectForKey:url];
                                                            });
                                                        }];
        // 是否需要解码
        operation.shouldDecompressImages = wself.shouldDecompressImages;
        
        if (wself.urlCredential) {
            operation.credential = wself.urlCredential;
        } else if (wself.username && wself.password) {
            operation.credential = [NSURLCredential credentialWithUser:wself.username password:wself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }

        // NSOperation Queue 增加一个对象
        //4.设置依赖
        // [operation2 addDependency:operation1];      任务二依赖任务一
        // [operation3 addDependency:operation2];      任务三依赖任务二
          // 6. 将操作加入到操作队列downloadQueue中
        [wself.downloadQueue addOperation:operation];
        // 如果不是FIFO 是 LIFO 队列设置依赖，后进来的成为上面的依赖
        if (wself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
            //FIFO的话正常数组就问题
            // LIFO的话让之前的操作一次依赖最后一次进来的操作就行了
            [wself.lastAddedOperation addDependency:operation];
            wself.lastAddedOperation = operation;
        }
    }];

    return operation;
}

// 增加到URLCallBacks操作
// completeBlock就是下载完回传的
// progressBlock就是下载进度回传的
//
- (void)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock completedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock forURL:(NSURL *)url createCallback:(SDWebImageNoParamsBlock)createCallback {
    // The URL will be used as the key to the callbacks dictionary so it cannot be nil. If it is nil immediately call the completed block with no image or data.
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return;
    }
    // 1. 以dispatch_barrier_sync操作来保证同一时间只有一个线程能对URLCallbacks进行操作
    // 该属性是一个字典，key是图片的URL地址，value则是一个数组，包含每个图片的多组回调信息。由于我们允许多个图片同时下载，因此可能会有多个线程同时操作URLCallbacks属性。为了保证URLCallbacks操作(添加、删除)的线程安全性，SDWebImageDownloader将这些操作作为一个个任务放到barrierQueue队列中，并设置屏障来确保同一时间只有一个线程操作URLCallbacks属性
    // 这个写法阻塞当前线程  而且阻塞barrierQueue队列
    // 这句话表示每个URL下载只会出来一次creatBlock回调出去创建新的任务operation（最终要添加到queue的任务）
    dispatch_barrier_sync(self.barrierQueue, ^{
        BOOL first = NO;
        if (!self.URLCallbacks[url]) {
            // 当第一次进来下载的时候，我们平时外部都是传个completeblock，所以我们的urlcallbacks结构是{"url":[{"comolete":"completeBlock"}]}
            // 如果是多次重复下载同一URL图片，结构应该会变成
            // {"url":[{"comolete":"completeBlock"},{"comolete":"completeBlock"},{"comolete":"completeBlock"},{"comolete":"completeBlock"}]}
            self.URLCallbacks[url] = [NSMutableArray new];
            first = YES;
        }

        // Handle single download of simultaneous download request for the same URL
        // 2. 处理同一URL的同步下载请求的单个下载
        NSMutableArray *callbacksForURL = self.URLCallbacks[url];
        NSMutableDictionary *callbacks = [NSMutableDictionary new];
        if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
        if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
        [callbacksForURL addObject:callbacks];
        self.URLCallbacks[url] = callbacksForURL;

        // 如果是第一次，那么回调出去下载
        if (first) {
            createCallback();
        }
    });
}

- (void)setSuspended:(BOOL)suspended {
    [self.downloadQueue setSuspended:suspended];
}

- (void)cancelAllDownloads {
    [self.downloadQueue cancelAllOperations];
}

#pragma mark Helper methods

- (SDWebImageDownloaderOperation *)operationWithTask:(NSURLSessionTask *)task {
    SDWebImageDownloaderOperation *returnOperation = nil;
    for (SDWebImageDownloaderOperation *operation in self.downloadQueue.operations) {
        if (operation.dataTask.taskIdentifier == task.taskIdentifier) {
            returnOperation = operation;
            break;
        }
    }
    return returnOperation;
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didCompleteWithError:error];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
}

@end
