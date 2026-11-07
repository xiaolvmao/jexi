// 探针：验证 Core Image 在本机命令行进程里能否放大并锐化图片。
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

int main(void) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        NSString *dir = [[NSFileManager defaultManager] currentDirectoryPath];

        // 造一张 800x600 的测试图
        size_t w = 800, h = 600;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(cs);
        for (int i = 0; i < 40; i++) {
            CGContextSetRGBFillColor(ctx, (i % 5) / 5.0, (i % 7) / 7.0, (i % 3) / 3.0, 1);
            CGContextFillRect(ctx, CGRectMake(i * 20, i * 13, 60, 40));
        }
        CGImageRef src = CGBitmapContextCreateImage(ctx);
        CGContextRelease(ctx);

        NSDate *start = [NSDate date];
        CIImage *input = [CIImage imageWithCGImage:src];
        CIFilter *scale = [CIFilter filterWithName:@"CILanczosScaleTransform"];
        if (scale == nil) {
            printf("没有 CILanczosScaleTransform\n");
            return 1;
        }
        [scale setValue:input forKey:kCIInputImageKey];
        [scale setValue:@2.0 forKey:kCIInputScaleKey];
        [scale setValue:@1.0 forKey:kCIInputAspectRatioKey];
        CIImage *scaled = scale.outputImage;
        printf("放大后 extent: %.0fx%.0f\n", scaled.extent.size.width, scaled.extent.size.height);

        CIFilter *sharpen = [CIFilter filterWithName:@"CIUnsharpMask"];
        [sharpen setValue:scaled forKey:kCIInputImageKey];
        [sharpen setValue:@2.0 forKey:@"inputRadius"];
        [sharpen setValue:@0.6 forKey:@"inputIntensity"];
        CIImage *sharpened = sharpen.outputImage;

        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef out = [context createCGImage:sharpened fromRect:sharpened.extent];
        if (out == NULL) {
            printf("createCGImage 失败\n");
            return 1;
        }
        printf("输出 %zux%zu，用时 %.2f 秒\n", CGImageGetWidth(out), CGImageGetHeight(out),
               [[NSDate date] timeIntervalSinceDate:start]);

        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"probe-enhanced.jpg"]];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
        CGImageDestinationAddImage(dest, out, (__bridge CFDictionaryRef)@{ (NSString *)kCGImageDestinationLossyCompressionQuality: @0.95 });
        BOOL ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        CGImageRelease(out);
        CGImageRelease(src);
        printf("写出: %d\n", ok);
    }
    return 0;
}
