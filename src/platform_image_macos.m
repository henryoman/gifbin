#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGBitmapContext.h>
#include <CoreGraphics/CGColorSpace.h>
#include <CoreGraphics/CGContext.h>
#include <CoreGraphics/CGGeometry.h>
#include <CoreGraphics/CGImage.h>
#include <ImageIO/CGImageSource.h>
#include <limits.h>
#include <math.h>
#include <string.h>

int gifbin_read_image_info(const char *path, int *out_width, int *out_height) {
    if (!path || !out_width || !out_height) return 0;

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault,
        (const UInt8 *)path,
        (CFIndex)strlen(path),
        false
    );
    if (!url) return 0;

    CGImageSourceRef source = CGImageSourceCreateWithURL(url, NULL);
    CFRelease(url);
    if (!source) return 0;

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return 0;

    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGImageRelease(image);
    if (width == 0 || height == 0 || width > INT_MAX || height > INT_MAX) return 0;

    *out_width = (int)width;
    *out_height = (int)height;
    return 1;
}

int gifbin_decode_image_rgba(const char *path, int width, int height, unsigned char *out_rgba) {
    if (!path || !out_rgba || width <= 0 || height <= 0) return 0;

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault,
        (const UInt8 *)path,
        (CFIndex)strlen(path),
        false
    );
    if (!url) return 0;

    CGImageSourceRef source = CGImageSourceCreateWithURL(url, NULL);
    CFRelease(url);
    if (!source) return 0;

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return 0;

    size_t src_w = CGImageGetWidth(image);
    size_t src_h = CGImageGetHeight(image);
    if (src_w == 0 || src_h == 0) {
        CGImageRelease(image);
        return 0;
    }

    CGColorSpaceRef color_space = CGColorSpaceCreateDeviceRGB();
    if (!color_space) {
        CGImageRelease(image);
        return 0;
    }

    CGContextRef ctx = CGBitmapContextCreate(
        out_rgba,
        (size_t)width,
        (size_t)height,
        8,
        (size_t)width * 4,
        color_space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(color_space);
    if (!ctx) {
        CGImageRelease(image);
        return 0;
    }

    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

    double scale = fmin((double)width / (double)src_w, (double)height / (double)src_h);
    double draw_w = (double)src_w * scale;
    double draw_h = (double)src_h * scale;
    double draw_x = ((double)width - draw_w) * 0.5;
    double draw_y = ((double)height - draw_h) * 0.5;

    CGContextDrawImage(ctx, CGRectMake(draw_x, draw_y, draw_w, draw_h), image);

    CGContextRelease(ctx);
    CGImageRelease(image);
    return 1;
}
