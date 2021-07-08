/*
 Copyright 2016-present Google Inc. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

@import AVFoundation;
@import MLKitBarcodeScanning;
@import MLKitVision;

#import "CameraViewController.h"

@interface CameraViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate>

@property(nonatomic, weak) IBOutlet UIView *placeHolderView;
@property(nonatomic, weak) IBOutlet UIView *overlayView;
@property(nonatomic, strong) UIImageView *imageView;

@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property(nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property(nonatomic, strong) MLKBarcodeScanner *barcodeDetector;
@property(nonatomic, strong) UIButton *torchButton;
@property(nonatomic, strong) UIImage *torchOn;
@property(nonatomic, strong) UIImage *torchOff;


@end

@implementation CameraViewController
@synthesize delegate;

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return YES;
}

- (BOOL) shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue",
                                                      DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Set up camera.
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetHigh;

    _videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue",
                                                  DISPATCH_QUEUE_SERIAL);

    [self updateCameraSelection];

    // Set up video processing pipeline.
    [self setUpVideoProcessing];

    // Set up camera preview.
    [self setUpCameraPreview];


    //Parse Cordova settings.
    NSNumber *formats = 0;
    //If barcodeFormats == 0 then process as a VIN with VIN verifications.
    if([_barcodeFormats  isEqual: @0]) {
        NSLog(@"Running VIN style");
        formats = @(MLKBarcodeFormatCode39|MLKBarcodeFormatDataMatrix);
    } else if([_barcodeFormats  isEqual: @1234]) {
        // @todo: investigating what should be done here
    } else {
        formats = _barcodeFormats;
    }
    NSLog(@"_barcodeFormats %@, %@", _barcodeFormats, formats);

    // Initialize barcode detector.
    MLKBarcodeScannerOptions *options = [[MLKBarcodeScannerOptions alloc] initWithFormats: [formats intValue]];
    self.barcodeDetector = [MLKBarcodeScanner barcodeScannerWithOptions:options];

    }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.previewLayer.frame = self.view.layer.bounds;
    self.previewLayer.position = CGPointMake(CGRectGetMidX(self.previewLayer.frame),
                                             CGRectGetMidY(self.previewLayer.frame));
}

- (void)viewDidUnload {
    [self cleanupCaptureSession];
    [super viewDidUnload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    //Force portrait orientation.
    [[UIDevice currentDevice] setValue:
     [NSNumber numberWithInteger: UIInterfaceOrientationPortrait]
                                forKey:@"orientation"];

    [self.session startRunning];

}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.session stopRunning];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {

    //Convert sampleBuffer into an image.
    //MLKVisionImage *image = [[MLKVisionImage alloc] initWithBuffer:sampleBuffer];
    CVImageBufferRef imageBuffer =
    CMSampleBufferGetImageBuffer(sampleBuffer);
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext
                             createCGImage:ciImage
                             fromRect:CGRectMake(0, 0,
                                                 CVPixelBufferGetWidth(imageBuffer),
                                                 CVPixelBufferGetHeight(imageBuffer))];

    UIImage *image = [[UIImage alloc] initWithCGImage:videoImage];
    CGImageRelease(videoImage);

    //We're going to crop UIImage to the onscreen viewfinder's box size for faster processing.
    UIImage *croppedImg = nil;

    //Define the crop coordinates.
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    CGFloat screenWidth = screenRect.size.width;
    CGFloat screenHeight = screenRect.size.height;
    
    CGFloat imageWidth = image.size.width;
    CGFloat imageHeight = image.size.height;
    
    CGFloat actualFrameWidth = 0;
    CGFloat actualFrameHeight = 0;
    
    //Figure out which ratio is bigger and then subtract a value off the frame width in case some of the camera preview is hanging off screen.
    if(imageWidth/screenWidth < imageHeight/screenHeight){
        actualFrameWidth = imageWidth * _scanAreaSize;
        actualFrameHeight = actualFrameWidth;
    } else {
        actualFrameHeight = imageHeight * _scanAreaSize;
        actualFrameWidth = actualFrameHeight;
    }

    //Define crop rectangle.
    CGRect cropRect = CGRectMake(imageWidth/2 - actualFrameWidth/2, imageHeight/2 - actualFrameHeight/2, actualFrameWidth, actualFrameHeight);

    //Crop image
    croppedImg = [self croppIngimageByImageName:image toRect:cropRect];

    //Rotate the image.
    MLKVisionImage *portraitImage = [[MLKVisionImage alloc] initWithImage:croppedImg];
    portraitImage.orientation = UIImageOrientationRight;

    //Send the image through the barcode reader.
    [self.barcodeDetector processImage:portraitImage completion:^(NSArray<MLKBarcode *> *barcodes,
                                                          NSError *error) {
        if (error != nil) {
            return;
        } else if (barcodes != nil) {
            for (MLKBarcode *barcode in barcodes) {
                NSLog(@"Barcode value: %@", barcode.rawValue);
                [self cleanupCaptureSession];
                [self->_session stopRunning];
                [self->delegate sendResult:barcode];
                break;
            }
        }
    }];

}

#pragma mark - Camera setup

- (void)cleanupVideoProcessing {
    if (self.videoDataOutput) {
        [self.session removeOutput:self.videoDataOutput];
    }
    self.videoDataOutput = nil;
}

- (void)cleanupCaptureSession {
    [self.session stopRunning];
    [self cleanupVideoProcessing];
    self.session = nil;
    [self.previewLayer removeFromSuperlayer];
}

- (void)setUpVideoProcessing {
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSDictionary *rgbOutputSettings = @{
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
    [self.videoDataOutput setVideoSettings:rgbOutputSettings];

    if (![self.session canAddOutput:self.videoDataOutput]) {
        [self cleanupVideoProcessing];
        NSLog(@"Failed to setup video output");
        return;
    }
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    [self.session addOutput:self.videoDataOutput];
}

- (void)setUpCameraPreview {
    self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    [self.previewLayer setBackgroundColor:[UIColor blackColor].CGColor];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];

    self.previewLayer.frame = self.view.superview.bounds;
    [self.view.layer addSublayer:self.previewLayer];

    CGRect screenRect = [[UIScreen mainScreen] bounds];
    CGFloat screenWidth = screenRect.size.width;
    CGFloat screenHeight = screenRect.size.height;

    CGFloat frameWidth = screenWidth*_scanAreaSize;
    CGFloat frameHeight = frameWidth;

    UILabel* _label1 = [[UILabel alloc] init];
    _label1.frame = CGRectMake(screenWidth/2 - frameWidth/2, screenHeight/2 - frameHeight/2, frameWidth, frameHeight);
    _label1.layer.masksToBounds = NO;
    _label1.layer.cornerRadius = 0;
    _label1.userInteractionEnabled = YES;
    _label1.layer.borderColor = [UIColor whiteColor].CGColor;
    _label1.layer.borderWidth = 1.0;
    UITapGestureRecognizer* tapScanner = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusAtPoint:)];
    [_label1 addGestureRecognizer:tapScanner];

    CGFloat buttonSize = 45.0;

    UIButton *_cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton addTarget:self
                      action:@selector(closeView:)
            forControlEvents:UIControlEventTouchUpInside];


    UIImage *cancelIcon = [UIImage imageNamed:@"closecamera"];
    [_cancelButton setImage:cancelIcon
                   forState:UIControlStateNormal];

    CGFloat screenOffset = (screenWidth/2 - frameWidth/2)/2 - buttonSize/2;
    NSLog(@"screenOffset %f", screenOffset);

    //_cancelButton.frame = CGRectMake(screenOffset, screenHeight-screenOffset-buttonSize, buttonSize, buttonSize);
    _cancelButton.frame = CGRectMake( 0, 0, cancelIcon.size.width+ 16, cancelIcon.size.height);
    _cancelButton.bounds = CGRectMake( 0, 0, cancelIcon.size.width+ 16, cancelIcon.size.height);
    _cancelButton.center = CGPointMake((screenWidth)/2, screenHeight*9/10);

    [self.view addSubview:_cancelButton];




    self.torchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.torchButton addTarget:self
                         action:@selector(toggleFlashlight:)
               forControlEvents:UIControlEventTouchUpInside];
    
    self.torchOn = [UIImage imageNamed:@"on-notxt"];
    self.torchOff = [UIImage imageNamed:@"off-notxt"];
    [self.torchButton setImage:self.torchOn forState:UIControlStateHighlighted];
    [self.torchButton setImage:self.torchOff forState:UIControlStateNormal];
    
    //self.torchButton.bounds = CGRectMake( 0, 10, torchOn.size.width, torchOn.size.height);
    self.torchButton.bounds = CGRectMake( 0, 0, self.torchOn.size.width+ 16, self.torchOn.size.height);
    self.torchButton.frame = CGRectMake( 0, 0, self.torchOn.size.width+ 16, self.torchOn.size.height);
    self.torchButton.center = CGPointMake((screenWidth)/2, screenHeight*8/10);
    
    
    UILabel* title = [[UILabel alloc] init];
    title.layer.cornerRadius = 0;
    title.text=self.title;
    title.bounds = CGRectMake(screenWidth*0.2, screenHeight*0.3, screenWidth*0.65,120 );
    title.frame = CGRectMake(screenWidth*0.2, screenHeight*0.3, screenWidth*0.65,120 );
    [title setFont:[UIFont boldSystemFontOfSize:20.0]];
    [title setTextAlignment:NSTextAlignmentCenter];//Set text alignment in label.
    title.lineBreakMode = NSLineBreakByWordWrapping;
    title.adjustsFontSizeToFitWidth=YES;
    [title setNumberOfLines:0];
    [title sizeToFit];
    title.center = CGPointMake((screenWidth)/2, screenHeight* 25/100);
    title.textColor= [UIColor whiteColor];
    
    

    [self.view addSubview:self.torchButton];

    [self.view addSubview:_label1];
    [self.view addSubview:title];
    

    self.imageView = [[UIImageView alloc] initWithImage:nil];

    UIView *catView = [[UIView alloc] initWithFrame:CGRectMake(0,0,frameWidth,frameHeight)];
    self.imageView.frame = catView.bounds;

    // add the imageview to the superview
    [catView addSubview:self.imageView];

    //add the view to the main view

    [self.view addSubview:catView];

}

#pragma mark - Helper Functions

- (void)focusAtPoint:(id) sender{
    NSLog(@"captured touch");
    CGPoint touchPoint = [(UITapGestureRecognizer*)sender locationInView:self.view];
    double focus_x = touchPoint.x/self.previewLayer.frame.size.width;
    double focus_y = (touchPoint.y+66)/self.previewLayer.frame.size.height;

    NSError *error;
    NSArray *devices = [AVCaptureDevice devices];
    for (AVCaptureDevice *device in devices){
        NSLog(@"Device name: %@", [device localizedName]);
        if ([device hasMediaType:AVMediaTypeVideo]) {
            if ([device position] == AVCaptureDevicePositionBack) {
                NSLog(@"Device position : back");
                CGPoint point = CGPointMake(focus_y, 1-focus_x);
                if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus] && [device lockForConfiguration:&error]){
                    [device setFocusPointOfInterest:point];

                    for (UIView *subView in self.view.subviews)
                    {
                        if (subView.tag == 99)
                        {
                            [subView removeFromSuperview];
                        }
                    }

                    CGRect rect = CGRectMake(touchPoint.x-30, touchPoint.y-30, 60, 60);
                    UIView *focusRect = [[UIView alloc] initWithFrame:rect];
                    focusRect.layer.borderColor = [UIColor colorWithRed:0.98 green:0.80 blue:0.18 alpha:.7].CGColor;
                    focusRect.layer.borderWidth = 1;
                    focusRect.tag = 99;
                    [self.view addSubview:focusRect];

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [focusRect removeFromSuperview];
                    });

                    [device setFocusMode:AVCaptureFocusModeAutoFocus];
                    [device unlockForConfiguration];
                }
            }
        }
    }
}
static inline double radians (double degrees) {return degrees * M_PI/180;}
- (UIImage*) rotateImage:(UIImage*)src toOrientation:(UIImageOrientation) orientation
{
    UIGraphicsBeginImageContext(src.size);

    CGContextRef context = UIGraphicsGetCurrentContext();

    if (orientation == UIImageOrientationRight) {
        CGContextRotateCTM (context, radians(90));
    } else if (orientation == UIImageOrientationLeft) {
        CGContextRotateCTM (context, radians(-90));
    } else if (orientation == UIImageOrientationDown) {
        // NOTHING
    } else if (orientation == UIImageOrientationUp) {
        CGContextRotateCTM (context, radians(90));
    }

    [src drawAtPoint:CGPointMake(0, 0)];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UIImage *)croppIngimageByImageName:(UIImage *)imageToCrop toRect:(CGRect)rect
{
    //CGRect CropRect = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height+15);

    CGImageRef imageRef = CGImageCreateWithImageInRect([imageToCrop CGImage], rect);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);

    return cropped;
}

- (void) toggleFlashlight:(id)sender
{
    // check if flashlight available
    Class captureDeviceClass = NSClassFromString(@"AVCaptureDevice");
    if (captureDeviceClass != nil) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if ([device hasTorch] && [device hasFlash]){

            [device lockForConfiguration:nil];
            if (device.torchMode == AVCaptureTorchModeOff)
            {
                //self.torchButton.backgroundColor = [UIColor colorWithWhite:1 alpha:1];
                [self.torchButton setImage:self.torchOn forState:UIControlStateNormal];
                [device setTorchMode:AVCaptureTorchModeOn];
                [device setFlashMode:AVCaptureFlashModeOn];
                //torchIsOn = YES;
            }
            else
            {
                //self.torchButton.backgroundColor = [UIColor colorWithWhite:1 alpha:.4];
                [self.torchButton setImage:self.torchOff forState:UIControlStateNormal];
                [device setTorchMode:AVCaptureTorchModeOff];
                [device setFlashMode:AVCaptureFlashModeOff];
                // torchIsOn = NO;
            }
            [device unlockForConfiguration];
        }
    } }

- (void) closeView :(id)sender{

    [ self cleanupCaptureSession];

    [_session stopRunning];

    [delegate closeScanner];
}


- (void)updateCameraSelection {
    [self.session beginConfiguration];

    // Remove old inputs
    NSArray *oldInputs = [self.session inputs];
    for (AVCaptureInput *oldInput in oldInputs) {
        [self.session removeInput:oldInput];
    }

    AVCaptureDevicePosition desiredPosition = AVCaptureDevicePositionBack;
    AVCaptureDeviceInput *input = [self captureDeviceInputForPosition:desiredPosition];
    if (!input) {
        // Failed, restore old inputs
        for (AVCaptureInput *oldInput in oldInputs) {
            [self.session addInput:oldInput];
        }
    } else {
        // Succeeded, set input and update connection states
        [self.session addInput:input];
    }
    [self.session commitConfiguration];
}

- (AVCaptureDeviceInput *)captureDeviceInputForPosition:(AVCaptureDevicePosition)desiredPosition {
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        if (device.position == desiredPosition) {
            NSError *error = nil;
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device
                                                                                error:&error];
            if (error) {
                NSLog(@"Could not initialize for AVMediaTypeVideo for device %@", device);
            } else if ([self.session canAddInput:input]) {
                return input;
            }
        }
    }
    return nil;
}



@end
