import UIKit
import SystemConfiguration

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, LiftServerDelegate {

    var deviceToken: NSData?
    var window: UIWindow?
    var alertView: UIAlertView? = nil
    var lastAlertTime: NSDate? = nil
    
    // MARK: Application-wide public functions
    
    class func becomeCurrentRemoteNotificationDelegate(delegate: RemoteNotificationDelegate) {
        (UIApplication.sharedApplication().delegate! as AppDelegate).currentRemoteNotificationDelegate = delegate
    }
    
    class func unbecomeCurrentRemoteNotificationDelegate() {
        (UIApplication.sharedApplication().delegate! as AppDelegate).currentRemoteNotificationDelegate = nil
    }
    
    class func becomeCurrentLiftServerDelegate(delegate: LiftServerDelegate) {
        (UIApplication.sharedApplication().delegate! as AppDelegate).currentLiftServerDelegate = delegate
    }
    
    class func unbecomeCurrentLiftServerDelegate() {
        (UIApplication.sharedApplication().delegate! as AppDelegate).currentLiftServerDelegate = nil
    }

    weak var currentRemoteNotificationDelegate: RemoteNotificationDelegate?
    var currentLiftServerDelegate: LiftServerDelegate?

    // MARK: Private functions
    
    private func startWithStoryboardId(storyboard: UIStoryboard, id: String) {
        window = UIWindow(frame: UIScreen.mainScreen().bounds)
        window!.makeKeyAndVisible()
        window!.rootViewController = storyboard.instantiateViewControllerWithIdentifier(id) as? UIViewController!
    }
    
    private func registerSettingsAndDelegates() {
        if UIDevice.currentDevice().systemVersion >= "8.0" {
            let settings = UIUserNotificationSettings(forTypes: UIUserNotificationType.Alert | UIUserNotificationType.Badge | UIUserNotificationType.Sound, categories: nil)
            UIApplication.sharedApplication().registerUserNotificationSettings(settings)
        } else {
            UIApplication.sharedApplication().registerForRemoteNotificationTypes(UIRemoteNotificationType.Alert | UIRemoteNotificationType.Badge | UIRemoteNotificationType.Sound)
        }
        
        UIApplication.sharedApplication().registerForRemoteNotifications()
        
        var acceptAction = UIMutableUserNotificationAction()
        acceptAction.title = NSLocalizedString("Accept", comment: "Accept invitation")
        acceptAction.identifier = "accept"
        acceptAction.activationMode = UIUserNotificationActivationMode.Background
        acceptAction.authenticationRequired = false
        
        var categories = NSMutableSet()
        var inviteCategory = UIMutableUserNotificationCategory()
        inviteCategory.setActions([acceptAction], forContext: UIUserNotificationActionContext.Default)
        inviteCategory.identifier = "invitation"
        categories.addObject(inviteCategory)
        
        let type = UIUserNotificationType.Alert | UIUserNotificationType.Badge | UIUserNotificationType.Sound
        let settings = UIUserNotificationSettings(forTypes: type, categories: categories)
        UIApplication.sharedApplication().registerUserNotificationSettings(settings)
        
        LiftServer.sharedInstance.setDelegate(self, delegateQueue: dispatch_get_main_queue())
    }
        
    // MARK: UIApplicationDelegate implementation

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // notifications et al
        registerSettingsAndDelegates()
        
        // main initialization
        // Prepare the cache
        LiftServerCache.sharedInstance.build { _ in
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            if let userId = CurrentLiftUser.userId {
                // We have previously-known user id. But is the account still there?
                LiftServer.sharedInstance.userCheckAccount(userId) { r in
                    if let x = self.deviceToken {
                        LiftServer.sharedInstance.userRegisterDeviceToken(userId, deviceToken: x)
                    }

                    //self.startWithStoryboardId(storyboard, id: r.cata({ err in if err.code == 404 { return "login" } else { return "offline" } }, { x in return "main" }))
                    
                    // notice that we have no concept of "offline": if the server is unreachable, we'll
                    // give the user the benefit of doubt.
                    
                    self.startWithStoryboardId(storyboard, id: r.cata({ err in if err.code == 404 { return "login" } else { return "main" } }, { x in return "main" }))
                }
            } else {
                self.startWithStoryboardId(storyboard, id: "login")
            }
        }

        return true
    }
    
    func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData) {
        self.deviceToken = deviceToken
        NSLog("Token \(deviceToken)")
    }
    
    func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
        let data: [UInt8] = [0x5A, 0xB8, 0x48, 0x05, 0xF8, 0xD0, 0xCC, 0x63, 0x0A, 0x89, 0x90, 0xA8, 0x4D, 0x48, 0x08, 0x41, 0xC3, 0x68, 0x40, 0x03, 0x6C, 0x12, 0x2C, 0x8E, 0x52, 0xA8, 0xDC, 0xFD, 0x68, 0xA6, 0xF6, 0xF8]
        let buf = UnsafePointer<[UInt8]>(data)
        let deviceToken = NSData(bytes: buf, length: data.count)
        self.deviceToken = deviceToken
        NSLog("Not registered \(error)")
    }
    
    func application(application: UIApplication, didRegisterUserNotificationSettings notificationSettings: UIUserNotificationSettings) {
        NSLog("settings %@", notificationSettings)
    }
    
    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        if let x = currentRemoteNotificationDelegate {
            x.remoteNotificationReceivedAlert("foo")
        } else if self.alertView == nil {
            let aps = userInfo["aps"] as [NSObject : AnyObject]
            let alert = aps["alert"] as String
            
            AudioServicesPlayAlertSound(1007)
            self.alertView = UIAlertView(title: "Exercise", message: alert, delegate: nil, cancelButtonTitle: nil)
            self.alertView!.show()
            let delay = dispatch_time(DISPATCH_TIME_NOW, Int64(2 * Double(NSEC_PER_SEC)))
            dispatch_after(delay, dispatch_get_main_queue()) {
                self.alertView!.dismissWithClickedButtonIndex(0, animated: true)
                self.alertView = nil
            }
        }
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        if LiftServer.sharedInstance.setBaseUrlString(LiftUserDefaults.liftServerUrl) {
            LiftServerCache.sharedInstance.build(const(()))
        }
    }
    
    func applicationDidReceiveMemoryWarning(application: UIApplication) {
        LiftServerCache.sharedInstance.clean()
    }
    
    // MARK: LiftServerDelegate implementation
    
    private func notTooLoud(f: @autoclosure () -> Void) -> Void {
        let minimumAlertTime: NSTimeInterval = 5.0
        if let x = lastAlertTime {
            if NSDate().timeIntervalSinceDate(x) < minimumAlertTime { return }
        }
        lastAlertTime = NSDate()
        f()
    }
    
    func liftServer(liftServer: LiftServer, availabilityStateChanged newState: AvailabilityState) {
        currentLiftServerDelegate?.liftServer(liftServer, availabilityStateChanged: newState)
        
        if newState.isOnline() {
            notTooLoud(RKDropdownAlert.title("Online".localized(), backgroundColor: UIColor.greenColor(), textColor: UIColor.blackColor(), time: 3))
            UINavigationBar.appearance().barTintColor = nil
        } else {
            notTooLoud(RKDropdownAlert.title("Offline".localized(), backgroundColor: UIColor.orangeColor(), textColor: UIColor.blackColor(), time: 3))
            UINavigationBar.appearance().barTintColor = UIColor.orangeColor()
        }
    }

}

