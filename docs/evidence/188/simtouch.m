// simtouch <udid> <down|up|move> <xRatio> <yRatio>  — touches through Simulator's own HID path.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dlfcn.h>
typedef void *(*MouseFn)(CGPoint *, CGPoint *, uint32_t, NSEventType, NSSize, uint32_t);
int main(int argc, const char **argv) { @autoreleasepool {
  dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW);
  void *kit = dlopen("/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW);
  MouseFn mouse = (MouseFn)dlsym(kit, "IndigoHIDMessageForMouseNSEvent");
  id ctx = [NSClassFromString(@"SimServiceContext") performSelector:@selector(sharedServiceContextForDeveloperDir:error:) withObject:@"/Applications/Xcode.app/Contents/Developer" withObject:nil];
  id set = [ctx performSelector:@selector(defaultDeviceSetWithError:) withObject:nil];
  id device = nil;
  for (id d in [set valueForKey:@"devices"]) if ([[[d valueForKey:@"UDID"] UUIDString] isEqual:@(argv[1])]) device = d;
  if (!device) { fprintf(stderr, "no device\n"); return 1; }
  NSError *err = nil;
  id client = [[NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient") alloc] performSelector:@selector(initWithDevice:error:) withObject:device withObject:(__bridge id)(void *)&err];
  if (!client) { fprintf(stderr, "client: %s\n", err.description.UTF8String); return 1; }
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  for (int i = 2; i + 2 < argc; i += 3) {
    NSString *kind = @(argv[i]);
    NSEventType type = [kind isEqual:@"down"] ? NSEventTypeLeftMouseDown : [kind isEqual:@"up"] ? NSEventTypeLeftMouseUp : NSEventTypeLeftMouseDragged;
    CGPoint p = CGPointMake(atof(argv[i + 1]), atof(argv[i + 2]));
    void *msg = mouse(&p, NULL, 0x32, type, NSMakeSize(1, 1), 0);
    void (^completion)(NSError *) = ^(NSError *e) { if (e) fprintf(stderr, "send: %s\n", e.description.UTF8String); dispatch_semaphore_signal(done); };
    NSMethodSignature *sig = [client methodSignatureForSelector:@selector(sendWithMessage:freeWhenDone:completionQueue:completion:)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = @selector(sendWithMessage:freeWhenDone:completionQueue:completion:);
    BOOL free = YES; dispatch_queue_t q = dispatch_get_global_queue(0, 0);
    [inv setArgument:&msg atIndex:2]; [inv setArgument:&free atIndex:3]; [inv setArgument:&q atIndex:4]; [inv setArgument:&completion atIndex:5];
    [inv invokeWithTarget:client];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    usleep(16000);
  }
}}
