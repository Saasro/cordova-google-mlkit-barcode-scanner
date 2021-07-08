@import MLKitBarcodeScanning;

#import "CDViOSScanner.h"

@class UIViewController;

@interface CDViOSScanner ()
{
    NSInteger _previousStatusBarStyle;
    UIInterfaceOrientation _previousOrientation;
}
@end


@implementation CDViOSScanner

- (void)pluginInitialize
{
    _previousStatusBarStyle = -1;
    _previousOrientation = UIInterfaceOrientationUnknown;
}


- (void) startScan:(CDVInvokedUrlCommand *)command
{
    NSDictionary* options;
       if (command.arguments.count == 0) {
         options = [NSDictionary dictionary];
       } else {
         options = command.arguments[0];
       }
    
    _previousOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    //Force portrait orientation.
    [[UIDevice currentDevice] setValue: [NSNumber numberWithInteger: UIInterfaceOrientationPortrait] forKey:@"orientation"];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Arguments %@", command.arguments);
        if(self->_scannerOpen == YES) 
        {
            //Scanner is currently open, throw error.
            NSArray *response = @[@"SCANNER_OPEN", @"", @""];
            CDVPluginResult *pluginResult=[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:response];
            
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } 
        else 
        {
            //Open scanner.
            self->_scannerOpen = YES;
            self.cameraViewController = [[CameraViewController alloc] init];
            self.cameraViewController.delegate = self;
            
            //Provide settings to the camera view.
            NSNumberFormatter* f = [[NSNumberFormatter alloc] init];
            f.numberStyle = NSNumberFormatterDecimalStyle;
            NSNumber* barcodeFormats = [command argumentAtIndex:0 withDefault:@1234];
            self.cameraViewController.scanAreaSize = 0.7;//(CGFloat)[[command argumentAtIndex:1 withDefault:@.5] floatValue];
            self.cameraViewController.barcodeFormats = barcodeFormats;
            self.cameraViewController.title = [command argumentAtIndex:2];
            self.cameraViewController.modalPresentationStyle = UIModalPresentationFullScreen;
            
            NSLog(@"scanAreaSize: %f, barcodeFormats: %@", self.cameraViewController.scanAreaSize, self.cameraViewController.barcodeFormats);
            
            [self.viewController presentViewController:self.cameraViewController animated: NO completion:nil];
            self->_callback = command.callbackId;
        }
    });
}

- (void)sendResult:(MLKBarcode *)barcode
{
    [self.cameraViewController dismissViewControllerAnimated:NO completion:nil];
    _scannerOpen = NO;
    NSDictionary *response = @{
        @"cancelled":@false,
        @"type":[NSString stringWithFormat: @"%ld", barcode.valueType],
        @"text":barcode.rawValue,
        @"format":[NSString stringWithFormat: @"%ld", barcode.format]
    };
    
    //NSArray* response = @[barcode.rawValue, @(barcode.format), @(barcode.valueType)];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:response];
    
    [self resetOrientation];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callback];
}

- (void)closeScanner
{
    [self.cameraViewController dismissViewControllerAnimated:NO completion:nil];
    _scannerOpen = NO;
    
   
    NSDictionary *response = @{
        @"cancelled":@true,
        @"type":@"",
        @"text":@"",
        @"format":@""
    };
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:response];
    
    [self resetOrientation];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callback];
}

- (void)resetOrientation
{
    if (_previousOrientation != UIInterfaceOrientationUnknown && _previousOrientation != UIInterfaceOrientationPortrait)
    {
        [[UIDevice currentDevice] setValue: [NSNumber numberWithInteger: _previousOrientation] forKey:@"orientation"];
        NSLog(@"Changing device orientation to previous orientation");
    }
}


- (void)show:(CDVInvokedUrlCommand*)command
{
    if (self.cameraViewController == nil) 
    {
        NSLog(@"Tried to show scanner after it was closed.");
        return;
    }
    
    if (_previousStatusBarStyle != -1) 
    {
        NSLog(@"Tried to show scanner while already shown");
        return;
    }
    
    _previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    _previousOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    __block UINavigationController* nav = [[UINavigationController alloc]
                                           initWithRootViewController:self.cameraViewController];

    nav.navigationBarHidden = YES;
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    
    __weak CDViOSScanner* weakSelf = self;
    
    // Run later to avoid the "took a long time" log message.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (weakSelf.cameraViewController != nil) 
        {
            CGRect frame = [[UIScreen mainScreen] bounds];
            UIWindow* tmpWindow = [[UIWindow alloc] initWithFrame:frame];
            UIViewController* tmpController = [[UIViewController alloc] init];
            [tmpWindow setRootViewController:tmpController];
            [tmpWindow setWindowLevel:UIWindowLevelNormal];
            [tmpWindow makeKeyAndVisible];
            [tmpController presentViewController:nav animated:NO completion:nil];
        }
    });
}

@end
