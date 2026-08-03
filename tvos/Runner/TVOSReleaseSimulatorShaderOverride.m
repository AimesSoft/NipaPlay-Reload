#import "TVOSReleaseSimulatorShaderOverride.h"

#import <Metal/Metal.h>
#import <TargetConditionals.h>
#import <objc/runtime.h>

#if TARGET_OS_SIMULATOR && !DEBUG

typedef id<MTLLibrary> _Nullable (*NipaNewLibraryWithDataImplementation)(
    id,
    SEL,
    dispatch_data_t,
    NSError *_Nullable *_Nullable);

static NipaNewLibraryWithDataImplementation gOriginalNewLibraryWithData;

static NSString *_Nullable NipaReplacementShaderNameForLength(size_t length) {
  switch (length) {
    case 0x3dc04:
      return @"impeller_entity_simulator";
    case 0x5a05:
      return @"impeller_modern_simulator";
    case 0x30b0:
      return @"impeller_framebuffer_blend_simulator";
    default:
      return nil;
  }
}

static id<MTLLibrary> _Nullable NipaNewLibraryWithSimulatorData(
    id device,
    SEL selector,
    dispatch_data_t data,
    NSError *_Nullable *_Nullable error) {
  NSString *shaderName =
      NipaReplacementShaderNameForLength(dispatch_data_get_size(data));
  if (shaderName == nil) {
    return gOriginalNewLibraryWithData(device, selector, data, error);
  }

  NSURL *shaderURL = [[NSBundle mainBundle] URLForResource:shaderName
                                            withExtension:@"metallib"];
  NSData *shaderData =
      shaderURL == nil ? nil : [NSData dataWithContentsOfURL:shaderURL];
  if (shaderData == nil) {
    NSLog(@"[NipaPlay] Missing tvOS simulator shader: %@", shaderName);
    return gOriginalNewLibraryWithData(device, selector, data, error);
  }

  dispatch_data_t simulatorData = dispatch_data_create(
      shaderData.bytes,
      shaderData.length,
      dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
      ^{
        // Keep the NSData backing storage alive until Metal releases its view.
        (void)shaderData;
      });
  NSLog(@"[NipaPlay] Using tvOS simulator shader: %@", shaderName);
  return gOriginalNewLibraryWithData(device, selector, simulatorData, error);
}

void NipaInstallTVOSReleaseSimulatorShaderOverride(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    SEL selector = NSSelectorFromString(@"newLibraryWithData:error:");
    Class deviceClass = object_getClass(device);
    Method method = class_getInstanceMethod(deviceClass, selector);
    if (device == nil || method == NULL) {
      NSLog(@"[NipaPlay] Unable to install tvOS simulator shader override");
      return;
    }

    gOriginalNewLibraryWithData =
        (NipaNewLibraryWithDataImplementation)method_getImplementation(method);
    const char *typeEncoding = method_getTypeEncoding(method);
    IMP replacement = (IMP)NipaNewLibraryWithSimulatorData;
    if (!class_addMethod(deviceClass, selector, replacement, typeEncoding)) {
      method_setImplementation(method, replacement);
    }
    NSLog(@"[NipaPlay] Installed tvOS Release simulator shader override");
  });
}

#else

void NipaInstallTVOSReleaseSimulatorShaderOverride(void) {}

#endif
