// 生成 App 图标（纯 CoreGraphics + CoreText，无需 UIApplication）。
// 用法：makeicon <输出目录>，写出 Icon-120/152/167/180/1024.png
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

static void DrawIcon(CGContextRef ctx, CGFloat size) {
    // 深蓝到青绿的斜向渐变底
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColorRef colors[2] = {
        CGColorCreate(space, (CGFloat[]){0.10, 0.13, 0.30, 1.0}),
        CGColorCreate(space, (CGFloat[]){0.05, 0.55, 0.52, 1.0}),
    };
    CFArrayRef colorArray = CFArrayCreate(NULL, (const void **)colors, 2, &kCFTypeArrayCallBacks);
    CGGradientRef gradient = CGGradientCreateWithColors(space, colorArray, NULL);
    CGContextDrawLinearGradient(ctx, gradient,
                                CGPointMake(0, size),
                                CGPointMake(size, 0), 0);
    CGColorRelease(colors[0]);
    CGColorRelease(colors[1]);
    CFRelease(colorArray);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);

    CGColorRef white95 = CGColorCreateGenericRGB(1, 1, 1, 0.95);
    CGColorRef white75 = CGColorCreateGenericRGB(1, 1, 1, 0.75);

    // 光圈环
    CGFloat cx = size * 0.5;
    CGFloat cy = size * 0.56;
    CGFloat radius = size * 0.255;
    CGFloat lineWidth = size * 0.05;
    CGContextSetStrokeColorWithColor(ctx, white95);
    CGContextSetLineWidth(ctx, lineWidth);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(cx - radius, cy - radius, radius * 2, radius * 2));

    // 光圈叶片：环内六条弦
    CGContextSetLineWidth(ctx, size * 0.028);
    CGContextSetStrokeColorWithColor(ctx, white75);
    for (int i = 0; i < 6; i++) {
        CGFloat start = (CGFloat)i * M_PI / 3.0 + M_PI / 12.0;
        CGFloat end = start + M_PI / 3.0;
        CGPoint p1 = CGPointMake(cx + cos(start) * radius, cy + sin(start) * radius);
        CGPoint p2 = CGPointMake(cx + cos(end) * radius, cy + sin(end) * radius);
        CGContextMoveToPoint(ctx, p1.x, p1.y);
        CGContextAddLineToPoint(ctx, p2.x, p2.y);
        CGContextStrokePath(ctx);
    }

    // 中心圆点
    CGContextSetFillColorWithColor(ctx, white95);
    CGFloat dot = size * 0.05;
    CGContextFillEllipseInRect(ctx, CGRectMake(cx - dot, cy - dot, dot * 2, dot * 2));

    // 字标 jexi
    CTFontRef font = CTFontCreateWithName(CFSTR("HelveticaNeue-Medium"), size * 0.16, NULL);
    CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
    NSDictionary *attrs = @{
        (__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
        (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)white,
        (__bridge NSString *)kCTKernAttributeName: @(size * 0.012),
    };
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"jexi" attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    CGRect bounds = CTLineGetBoundsWithOptions(line, 0);
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextSetTextPosition(ctx, cx - bounds.size.width / 2.0 - bounds.origin.x, size * 0.13);
    CTLineDraw(line, ctx);
    CFRelease(line);
    CGColorRelease(white);
    CFRelease(font);
    CGColorRelease(white95);
    CGColorRelease(white75);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *outputDirectory = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @".";
        NSArray<NSNumber *> *sizes = @[@120, @152, @167, @180, @1024];
        for (NSNumber *sizeNumber in sizes) {
            CGFloat size = sizeNumber.doubleValue;
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)size, (size_t)size, 8, 0,
                                                     space, kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if (ctx == NULL) {
                printf("无法创建位图 %d\n", sizeNumber.intValue);
                return 1;
            }
            DrawIcon(ctx, size);
            CGImageRef image = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            if (image == NULL) {
                printf("无法生成图片 %d\n", sizeNumber.intValue);
                return 1;
            }
            NSString *name = [NSString stringWithFormat:@"Icon-%d.png", sizeNumber.intValue];
            NSURL *url = [NSURL fileURLWithPath:[outputDirectory stringByAppendingPathComponent:name]];
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                                                                CFSTR("public.png"), 1, NULL);
            CGImageDestinationAddImage(destination, image, NULL);
            BOOL ok = CGImageDestinationFinalize(destination);
            CFRelease(destination);
            CGImageRelease(image);
            printf("%s %s\n", name.UTF8String, ok ? "已写出" : "写出失败");
            if (!ok) {
                return 1;
            }
        }
    }
    return 0;
}
