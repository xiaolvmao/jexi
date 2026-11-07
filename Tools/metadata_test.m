// 命令行自测：不经过界面，验证 EXIF 重写是否按预期生效。
// 编译方式见 AGENTS.md，不属于 App 本体。
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreLocation/CoreLocation.h>
#import "EXMetadata.h"
#import "EXDevice.h"

static NSURL *MakeTestJPEG(NSString *name) {
    size_t width = 64, height = 48;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4,
                                                 colorSpace, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(context, 0.2, 0.6, 0.9, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                        CFSTR("public.jpeg"), 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    if (!ok) {
        NSLog(@"无法生成测试图");
        exit(1);
    }
    return url;
}

static int failures = 0;

static void Expect(NSString *label, BOOL condition, NSString *detail) {
    printf("%s %s%s\n", condition ? "PASS" : "FAIL", label.UTF8String,
           detail.length > 0 ? [NSString stringWithFormat:@" — %@", detail].UTF8String : "");
    if (!condition) {
        failures++;
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("设备: %s / %s / %s\n", [EXDevice marketingName].UTF8String,
               [EXDevice machineIdentifier].UTF8String, [EXDevice systemDescription].UTF8String);

        NSURL *source = MakeTestJPEG(@"exifone-in.jpg");
        NSURL *withGPS = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"exifone-gps.jpg"]];
        NSURL *withoutGPS = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"exifone-nogps.jpg"]];

        CLLocation *location = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(31.230416, 121.473701)
                                                            altitude:12.0
                                                  horizontalAccuracy:5.0
                                                    verticalAccuracy:5.0
                                                           timestamp:[NSDate date]];

        NSError *error = nil;
        BOOL ok = [EXMetadata writeSourceURL:source toDestination:withGPS
                                     options:(EXWriteDevice | EXWriteTime | EXWriteLocation)
                                    location:location date:nil format:EXOutputFormatKeep error:&error];
        Expect(@"写入（含定位）", ok, ok ? @"" : error.localizedDescription);

        NSDictionary *props = [EXMetadata propertiesAtURL:withGPS];
        NSDictionary *tiff = props[(NSString *)kCGImagePropertyTIFFDictionary];
        NSDictionary *exif = props[(NSString *)kCGImagePropertyExifDictionary];
        NSDictionary *gps = props[(NSString *)kCGImagePropertyGPSDictionary];

        Expect(@"TIFF.Make = Apple", [tiff[(NSString *)kCGImagePropertyTIFFMake] isEqual:@"Apple"],
               tiff[(NSString *)kCGImagePropertyTIFFMake]);
        Expect(@"TIFF.Model = 真实机型", [tiff[(NSString *)kCGImagePropertyTIFFModel] isEqual:[EXDevice marketingName]],
               tiff[(NSString *)kCGImagePropertyTIFFModel]);
        Expect(@"TIFF.Software = 系统版本", [tiff[(NSString *)kCGImagePropertyTIFFSoftware] isEqual:[EXDevice systemDescription]],
               tiff[(NSString *)kCGImagePropertyTIFFSoftware]);
        Expect(@"EXIF.DateTimeOriginal 非空", [exif[(NSString *)kCGImagePropertyExifDateTimeOriginal] length] > 0,
               exif[(NSString *)kCGImagePropertyExifDateTimeOriginal]);
        Expect(@"EXIF.OffsetTimeOriginal 有时区",
               [[exif[(NSString *)kCGImagePropertyExifOffsetTimeOriginal] description] hasPrefix:@"+"] ||
               [[exif[(NSString *)kCGImagePropertyExifOffsetTimeOriginal] description] hasPrefix:@"-"],
               [exif[(NSString *)kCGImagePropertyExifOffsetTimeOriginal] description]);
        Expect(@"EXIF.LensModel 非空", [exif[(NSString *)kCGImagePropertyExifLensModel] length] > 0,
               exif[(NSString *)kCGImagePropertyExifLensModel]);
        Expect(@"GPS 纬度接近真实值", fabs([gps[(NSString *)kCGImagePropertyGPSLatitude] doubleValue] - 31.230416) < 0.0001,
               [gps[(NSString *)kCGImagePropertyGPSLatitude] description]);
        Expect(@"GPS 经度接近真实值", fabs([gps[(NSString *)kCGImagePropertyGPSLongitude] doubleValue] - 121.473701) < 0.0001,
               [gps[(NSString *)kCGImagePropertyGPSLongitude] description]);
        Expect(@"GPS 日期戳存在", [gps[(NSString *)kCGImagePropertyGPSDateStamp] length] > 0,
               gps[(NSString *)kCGImagePropertyGPSDateStamp]);

        CGImageSourceRef outSource = CGImageSourceCreateWithURL((__bridge CFURLRef)withGPS, NULL);
        NSDictionary *imageProps = outSource ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(outSource, 0, NULL) : nil;
        if (outSource) {
            CFRelease(outSource);
        }
        Expect(@"像素尺寸保留", [imageProps[(NSString *)kCGImagePropertyPixelWidth] intValue] == 64 &&
              [imageProps[(NSString *)kCGImagePropertyPixelHeight] intValue] == 48,
               [NSString stringWithFormat:@"%@x%@", imageProps[(NSString *)kCGImagePropertyPixelWidth],
                imageProps[(NSString *)kCGImagePropertyPixelHeight]]);

        NSError *secondError = nil;
        BOOL ok2 = [EXMetadata writeSourceURL:withGPS toDestination:withoutGPS
                                      options:(EXWriteDevice | EXWriteTime)
                                     location:nil date:nil format:EXOutputFormatKeep error:&secondError];
        NSDictionary *props2 = [EXMetadata propertiesAtURL:withoutGPS];
        Expect(@"关闭定位后 GPS 被抹掉",
               ok2 && props2[(NSString *)kCGImagePropertyGPSDictionary] == nil,
               ok2 ? @"" : secondError.localizedDescription);

        // 新增的曝光/镜头参数
        Expect(@"EXIF.ExposureTime 已写", [exif[(NSString *)kCGImagePropertyExifExposureTime] doubleValue] > 0,
               [exif[(NSString *)kCGImagePropertyExifExposureTime] description]);
        Expect(@"EXIF.ISO 已写",
               [exif[(NSString *)kCGImagePropertyExifISOSpeedRatings] isKindOfClass:[NSArray class]] &&
               [exif[(NSString *)kCGImagePropertyExifISOSpeedRatings] count] > 0,
               [exif[(NSString *)kCGImagePropertyExifISOSpeedRatings] description]);
        Expect(@"EXIF.ApertureValue 已写", exif[(NSString *)kCGImagePropertyExifApertureValue] != nil,
               [exif[(NSString *)kCGImagePropertyExifApertureValue] description]);
        Expect(@"EXIF.LensSpecification 已写", [exif[(NSString *)kCGImagePropertyExifLensSpecification] count] == 4,
               [exif[(NSString *)kCGImagePropertyExifLensSpecification] description]);
        Expect(@"TIFF.ResolutionUnit 已写", tiff[(NSString *)kCGImagePropertyTIFFResolutionUnit] != nil,
               [tiff[(NSString *)kCGImagePropertyTIFFResolutionUnit] description]);

        // 转成 HEIF
        NSURL *heic = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                              stringByAppendingPathComponent:@"exifone.heic"]];
        NSError *heicError = nil;
        BOOL ok3 = [EXMetadata writeSourceURL:source toDestination:heic
                                      options:(EXWriteDevice | EXWriteTime | EXWriteLocation)
                                     location:location date:nil format:EXOutputFormatHEIF error:&heicError];
        CGImageSourceRef heicSource = ok3 ? CGImageSourceCreateWithURL((__bridge CFURLRef)heic, NULL) : NULL;
        CFStringRef heicType = heicSource ? CGImageSourceGetType(heicSource) : NULL;
        BOOL isHEIC = (heicType != NULL && CFEqual(heicType, CFSTR("public.heic")));
        NSDictionary *heicProps = nil;
        if (heicSource) {
            heicProps = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(heicSource, 0, NULL);
            CFRelease(heicSource);
        }
        Expect(@"转换成 HEIF", ok3 && isHEIC, ok3 ? [heic.pathExtension description] : heicError.localizedDescription);
        Expect(@"HEIF 保留尺寸",
               [heicProps[(NSString *)kCGImagePropertyPixelWidth] intValue] == 64 &&
               [heicProps[(NSString *)kCGImagePropertyPixelHeight] intValue] == 48,
               [NSString stringWithFormat:@"%@x%@", heicProps[(NSString *)kCGImagePropertyPixelWidth],
                heicProps[(NSString *)kCGImagePropertyPixelHeight]]);
        Expect(@"HEIF 写入机型",
               [heicProps[(NSString *)kCGImagePropertyTIFFDictionary][(NSString *)kCGImagePropertyTIFFModel]
                isEqual:[EXDevice marketingName]],
               heicProps[(NSString *)kCGImagePropertyTIFFDictionary][(NSString *)kCGImagePropertyTIFFModel]);
        Expect(@"HEIF 写入坐标",
               heicProps[(NSString *)kCGImagePropertyGPSDictionary][(NSString *)kCGImagePropertyGPSLatitude] != nil,
               [heicProps[(NSString *)kCGImagePropertyGPSDictionary][(NSString *)kCGImagePropertyGPSLatitude] description]);

        NSURL *heicNoGPS = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                                   stringByAppendingPathComponent:@"exifone-nogps.heic"]];
        NSError *heicStripError = nil;
        BOOL ok4 = [EXMetadata writeSourceURL:heic toDestination:heicNoGPS
                                      options:(EXWriteDevice | EXWriteTime) location:nil date:nil
                                       format:EXOutputFormatKeep error:&heicStripError];
        NSDictionary *heicPropsNoGPS = [EXMetadata propertiesAtURL:heicNoGPS];
        Expect(@"HEIF 上也能剥离 GPS",
               ok4 && heicPropsNoGPS[(NSString *)kCGImagePropertyGPSDictionary] == nil,
               ok4 ? @"" : heicStripError.localizedDescription);

        // 指定时间
        NSDate *fixedDate = [NSDate dateWithTimeIntervalSince1970:1700000000];
        NSDateFormatter *fixedFormatter = [[NSDateFormatter alloc] init];
        fixedFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fixedFormatter.timeZone = [NSTimeZone localTimeZone];
        fixedFormatter.dateFormat = @"yyyy:MM:dd HH:mm:ss";
        NSString *expected = [fixedFormatter stringFromDate:fixedDate];
        NSURL *fixedURL = [NSURL fileURLWithPath:[[[NSFileManager defaultManager] currentDirectoryPath]
                                                  stringByAppendingPathComponent:@"exifone-fixed.jpg"]];
        NSError *fixedError = nil;
        BOOL okFixed = [EXMetadata writeSourceURL:source toDestination:fixedURL
                                          options:(EXWriteDevice | EXWriteTime) location:nil
                                             date:fixedDate format:EXOutputFormatKeep error:&fixedError];
        NSString *written = [EXMetadata propertiesAtURL:fixedURL][(NSString *)kCGImagePropertyExifDictionary][(NSString *)kCGImagePropertyExifDateTimeOriginal];
        Expect(@"指定的时间按本地时区写入", okFixed && [written isEqualToString:expected],
               [NSString stringWithFormat:@"期望 %@ 实际 %@", expected, written]);

        printf("\n--- 摘要（第一张）---\n");
        for (NSDictionary *row in [EXMetadata summaryRowsFromProperties:props]) {
            printf("%s: %s\n", [row[@"key"] UTF8String], [row[@"value"] UTF8String]);
        }
        printf("\n--- 全部字段（第一张，前 40 条）---\n");
        NSArray *rows = [EXMetadata rowsFromProperties:props];
        for (NSUInteger i = 0; i < rows.count && i < 40; i++) {
            printf("%s.%s = %s\n", [rows[i][@"section"] UTF8String], [rows[i][@"key"] UTF8String],
                   [rows[i][@"value"] UTF8String]);
        }

        printf("\n%s\n", failures == 0 ? "全部通过" : "有失败项");
        return failures == 0 ? 0 : 1;
    }
}
