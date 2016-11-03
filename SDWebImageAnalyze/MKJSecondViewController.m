//
//  MKJSecondViewController.m
//  SDWebImageAnalyze
//
//  Created by MKJING on 16/10/21.
//  Copyright © 2016年 MKJING. All rights reserved.
//

#import "MKJSecondViewController.h"
#import "MKJCache.h"

@interface MKJSecondViewController ()

@end

@implementation MKJSecondViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    for (NSInteger i = 0; i < 10 ; i ++) {
        NSNumber *num = [[MKJCache shareCCache] queryValueForKey:[NSString stringWithFormat:@"%ld",i]];
        NSLog(@"测试存储数据222222=====>%@",num);
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
