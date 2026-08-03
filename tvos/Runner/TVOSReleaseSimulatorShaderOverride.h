#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Makes the device-release Flutter engine usable for local AOT runs in the
/// tvOS simulator. The implementation is compiled out for Debug and devices.
void NipaInstallTVOSReleaseSimulatorShaderOverride(void);

NS_ASSUME_NONNULL_END
