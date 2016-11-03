//
//  ViewController.m
//  SDWebImageAnalyze
//
//  Created by MKJING on 16/10/17.
//  Copyright © 2016年 MKJING. All rights reserved.
//

#import "ViewController.h"
#import "UIImageView+WebCache.h"
#import "MKJSecondViewController.h"
#import "MKJCache.h"
#import "WMProgressView.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (nonatomic,strong) WMProgressView *progressView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    __weak typeof(self)weakSelf = self;
    [self.imageView sd_setImageWithURL:[NSURL URLWithString:@"http://cdn.duitang.com/uploads/item/201111/08/20111108113800_wYcvP.thumb.600_0.jpg"] placeholderImage:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
       
        if (image && cacheType == SDImageCacheTypeNone)
        {
            weakSelf.imageView.alpha = 0;
            [UIView animateWithDuration:1.0f animations:^{
               
                weakSelf.imageView.alpha = 1.f;
            }];
        }
        else
        {
            weakSelf.imageView.alpha = 1.0f;
        }
        
    }];
    NSString *path = [[SDImageCache sharedImageCache] makeDiskCachePath:@"http://pic.baa.bitautotech.com/img/V2pic.baa.bitautotech.com/usergroup/2013/6/25/ab8ec6ba857945418bc5f0b5ac691d30_700_0_max_jpg.jpg"];
    NSLog(@"%@",path);
    
// 死锁
//    dispatch_queue_t queue = dispatch_queue_create("com.taowaitao.serialQueue", DISPATCH_QUEUE_SERIAL);
//    NSLog(@"1"); // 任务1
//    dispatch_async(queue, ^{
//        NSLog(@"2"); // 任务2
//        dispatch_sync(queue, ^{
//            NSLog(@"3"); // 任务3
//        });
//        NSLog(@"4"); // 任务4
//    });
//    NSLog(@"5"); // 任务5
    
    // 死锁例子
//    dispatch_queue_t queue =  dispatch_queue_create("zy", NULL);
//    dispatch_sync(queue, ^{
//        NSLog(@"123%@",[NSThread currentThread]);
//        dispatch_sync(queue, ^{
//            NSLog(@"234%@",[NSThread currentThread]);
//        });
//    });
    
    
    // 解决方案一
     dispatch_queue_t queue =  dispatch_queue_create("zy", NULL);
    dispatch_queue_t queue1 = dispatch_queue_create("zy1", NULL);
    dispatch_sync(queue, ^{
        NSLog(@"123");
       dispatch_sync(queue1, ^{
           NSLog(@"234");
       });
        
    });
    
    // 解决方案二
    dispatch_sync(queue, ^{
        NSLog(@"123");
        dispatch_async(queue1, ^{
            NSLog(@"234");
        });
        
    });
    
    
    // 测试NSCache
    for (NSInteger i = 0; i < 10; i ++)
    {
        [[MKJCache shareCCache] storeValue:@(i) forKey:[NSString stringWithFormat:@"%ld",i]];
    }
    
    
    
    self.progressView = [[WMProgressView alloc] initWithFrame:CGRectMake(0, 500, 375, 50)];
    
    CGRect rec = CGRectMake(0, 0, 50, 10);
    CGRect rec1 = CGRectMake(0, 0, 50, 10);
    CGRect rec2 = CGRectMake(0, 0, 50, 10);
    CGRect rec3 = CGRectMake(0, 0, 50, 10);
    self.progressView.itemFrames = @[[NSValue valueWithCGRect:rec],[NSValue valueWithCGRect:rec1],[NSValue valueWithCGRect:rec2],[NSValue valueWithCGRect:rec3]];
    [self.view addSubview:self.progressView];
    
    
   
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
//    for (NSInteger i = 0; i < 10 ; i ++) {
//        NSNumber *num = [[MKJCache shareCCache] queryValueForKey:[NSString stringWithFormat:@"%ld",i]];
//        NSLog(@"测试存储数据111111=====>%@",num);
//    }
//    MKJSecondViewController *sec = [[MKJSecondViewController alloc] init];
//    [self.navigationController pushViewController:sec animated:YES];
    
    [self.progressView moveToPostion:2];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
