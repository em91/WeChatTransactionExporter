/* How to Hook with Logos
Hooks are written with syntax similar to that of an Objective-C @implementation.
You don't need to #include <substrate.h>, it will be done automatically, as will
the generation of a class list and an automatic constructor.
*/

#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class WCBizLoadingView;

@interface PHRecentsViewController : UIViewController
- (void)shareExportResults: (NSArray *)results;
- (void)getOrdersWithOffset:(int)offset;
@end

%hook WCPayNewOrderHistoryViewController

- (void)getOrdersWithOffset:(int)offset {
	%log;
	[[NSUserDefaults standardUserDefaults] setValue:@(offset) forKey:@"_wechatPayExporter_offset_"];

	%orig;
}

- (void)viewDidLoad {
	%log;
	%orig;

	//reset crawling mode when page is pushed into navigation
   [[NSUserDefaults standardUserDefaults] setValue:@(NO) forKey:@"_wechatPayExporter_fetchModeOn_"];
}

- (void)handleGetOrderResponse:(NSDictionary *)response error:(id)error {
	%log;

	if (error != nil) {
		%orig;
       return;
   }

   //save total records number for auto crawling
   NSInteger totalNum = [[response objectForKey:@"TotalNum"] integerValue];
   [[NSUserDefaults standardUserDefaults] setValue:@(totalNum) forKey:@"_wechatPayExporter_totalNum_"];

   //show alertview when page is pushed into navigation
   NSInteger offset = [[[NSUserDefaults standardUserDefaults] valueForKey:@"_wechatPayExporter_offset_"] integerValue];
   if( offset == 0 ) {
       [[NSUserDefaults standardUserDefaults] setValue:nil forKey:@"_wechatPayExporter_results_"];

       UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"提示" message:@"开始导出微信交易记录？" preferredStyle:UIAlertControllerStyleAlert];

       UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"是的，开始导出" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
           NSInteger totalNum = [[[NSUserDefaults standardUserDefaults] valueForKey:@"_wechatPayExporter_totalNum_"] integerValue];
           NSInteger offset = [[[NSUserDefaults standardUserDefaults] valueForKey:@"_wechatPayExporter_offset_"] integerValue];

           if( offset + 20 <= totalNum ) {

               UIView *loadingView = [[NSClassFromString(@"WCBizLoadingView") alloc] init];
               ((UIView *)loadingView).tag = 1379;
               [loadingView performSelector:@selector(setTitle:) withObject:@"导出交易记录"];
               [loadingView performSelector:@selector(setMessage:) withObject:[NSString stringWithFormat:@"20/%@", @(totalNum)]];

               [[(UIViewController *)self view] addSubview:loadingView];
               [loadingView performSelector:@selector(startLoading)];

               [[NSUserDefaults standardUserDefaults] setValue:@(1) forKey:@"_wechatPayExporter_fetchModeOn_"];
               [self getOrdersWithOffset:offset + 20];
           }
           //less than 20 reords
           else {
               NSMutableArray *results = [[[NSUserDefaults standardUserDefaults] valueForKey:@"_wechatPayExporter_results_"] mutableCopy];
               [self shareExportResults:results];
           }
       }];
       [controller addAction:okAction];

       UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"不了，随便看看" style:UIAlertActionStyleDefault handler:nil];
       [controller addAction:cancelAction];

       [(UIViewController *)self presentViewController: controller animated: YES completion: nil];
   }

   NSArray *array = [response objectForKey:@"UserRollList"];

   NSMutableArray *results = [[[NSUserDefaults standardUserDefaults] valueForKey:@"_wechatPayExporter_results_"] mutableCopy];
   if (results == nil) {
       results = [@[] mutableCopy];
   }
   [results addObjectsFromArray:array];

   [[NSUserDefaults standardUserDefaults] setValue:results forKey:@"_wechatPayExporter_results_"];

   %orig;

   //crawling mode, call getOrders automatically
   BOOL isFetchMode = [[[NSUserDefaults standardUserDefaults] valueForKey:@"_wechatPayExporter_fetchModeOn_"] boolValue];
   if (isFetchMode) {
       WCBizLoadingView *loadingView = (WCBizLoadingView *)[[(UIViewController *)self view] viewWithTag:1379];
       [loadingView performSelector:@selector(setMessage:) withObject:[NSString stringWithFormat:@"%@/%@", @(results.count), @(totalNum)]];
       if( totalNum > offset + array.count && array.count > 0 ) {
           [self getOrdersWithOffset:offset + array.count];
       } else {
           [[NSUserDefaults standardUserDefaults] setValue:@(NO) forKey:@"_wechatPayExporter_fetchModeOn_"];
           [loadingView performSelector:@selector(removeFromSuperview)];

           [self shareExportResults:results];
       }
   }
}

%new
- (void)shareExportResults: (NSArray *)results
{
	NSMutableString *writeString = [NSMutableString stringWithCapacity:0]; //don't worry about the capacity, it will expand as necessary

	[writeString appendString:@"交易号, 流水号, 币种, 全部金额, 实付金额, 商品名称, 支付方式, 创建时间, 交易状态\n"];

	for (int i = 0; i < [results count]; i++) {
		NSDictionary *record = [results objectAtIndex:i] ;

		NSString *billId = [record objectForKey:@"BillId"];
		NSString *transId = [record objectForKey:@"Transid"];
		NSString *feeType = [record objectForKey:@"FeeType"];

		NSString *goodsName = [record objectForKey:@"GoodsName"];

		[writeString appendString:[NSString stringWithFormat:@"%@, %@, %@, %@, %@, %@, %@, %@, %@\n", billId, transId, feeType, [record objectForKey:@"TotalFee"], [record objectForKey:@"ActualPayFee"], goodsName, [record objectForKey:@"PayType"], [record objectForKey:@"CreateTime"], [record objectForKey:@"TradeStateName"]]]; //the \n will put a newline in
	}

	NSArray *dirPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *docsDir = [dirPaths firstObject];
	NSString *filePath = [[NSString alloc] initWithString: [docsDir stringByAppendingPathComponent:@"微信交易记录.csv"]];

	NSError *error = nil;
	[writeString writeToFile:filePath atomically:NO encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000) error:&error];

	if (error != nil) {
		NSLog(@"### Write to file fail, %@", error);
		return;
	}

	UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:filePath]] applicationActivities:nil];

	[self presentViewController:activityViewController animated:YES completion:nil];
}

%end
