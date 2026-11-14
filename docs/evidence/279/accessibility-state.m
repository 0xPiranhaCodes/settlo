#import <UIKit/UIKit.h>
int main() { @autoreleasepool { printf("ReduceTransparency=%d ReduceMotion=%d IncreaseContrast=%d\n",UIAccessibilityIsReduceTransparencyEnabled(),UIAccessibilityIsReduceMotionEnabled(),UIAccessibilityDarkerSystemColorsEnabled()); } }
