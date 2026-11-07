// 自测：验证 EXEnhancer 放大后的尺寸与可读性。
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import "EXEnhancer.h"

static NSURL *MakeTestJPEG(NSString *name, size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    for (int i = 0; i < 20; i++) {
        CGContextSetRGBFillColor(context, (i % 5) / 5.0, (i % 7) / 7.0, (i % 3) / 3.0, 1);
        CGContextFillRect(context, CGRectMake(i * 9, i * 6, 30, 20));
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    NSURL *url = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                         stringByAppendingPathComponent:name]];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                        CFSTR("public.jpeg"), 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    return url;
}

int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        NSURL *source = MakeTestJPEG(@"enh-in.jpg", 200, 150);
        NSURL *output = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                                stringByAppendingPathComponent:@"enh-out.jpg"]];
        NSError *error = nil;
        BOOL ok = [EXEnhancer upscaleURL:source toURL:output scale:2.0 maxDimension:8192 error:&error];
        printf("%s 放大 2 倍: %s\n", ok ? "PASS" : "FAIL", ok ? "" : error.localizedDescription.UTF8String);

        CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)output, NULL);
        NSDictionary *properties = imageSource
            ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL) : nil;
        if (imageSource) {
            CFRelease(imageSource);
        }
        int width = [properties[(NSString *)kCGImagePropertyPixelWidth] intValue];
        int height = [properties[(NSString *)kCGImagePropertyPixelHeight] intValue];
        printf("%s 输出尺寸 400x300: 实际 %dx%d\n", (width == 400 && height == 300) ? "PASS" : "FAIL", width, height);

        // 超上限时自动降倍数
        NSURL *bigOutput = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                                   stringByAppendingPathComponent:@"enh-big.jpg"]];
        BOOL ok2 = [EXEnhancer upscaleURL:source toURL:bigOutput scale:4.0 maxDimension:300 error:&error];
        CGImageSourceRef bigSource = CGImageSourceCreateWithURL((__bridge CFURLRef)bigOutput, NULL);
        NSDictionary *bigProperties = bigSource
            ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(bigSource, 0, NULL) : nil;
        if (bigSource) {
            CFRelease(bigSource);
        }
        int bigWidth = [bigProperties[(NSString *)kCGImagePropertyPixelWidth] intValue];
        printf("%s 长边上限 300 生效: %dx%d\n", (ok2 && bigWidth <= 300) ? "PASS" : "FAIL",
               bigWidth, [bigProperties[(NSString *)kCGImagePropertyPixelHeight] intValue]);
    }
    return 0;
}
