import Foundation
import GoogleMobileAds

public class GADUtil: NSObject {
    public static let share = GADUtil()
    
    private static var positionsValue: [GADPosition]?
    public static var positions: [GADPosition] {
        guard let value = positionsValue else {
            fatalError("positions has not been initialized")
        }
        return value
    }

    public static func initializePositions(_ value: [GADPosition]) {
        guard positionsValue == nil else {
            fatalError("positions has already been initialized")
        }
        positionsValue = value
    }
    override init() {
        super.init()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.ads.forEach {
                $0.loadedArray = $0.loadedArray.filter({ model in
                    if model.position.isOpen {
                        let expired = Double(self.config?.openExpired ?? 60)
                        return model.loadedDate?.isExpired(with: expired * 60) == false
                    } else {
                        let expired = Double(self.config?.interstitialExpired ?? 60)
                        return model.loadedDate?.isExpired(with: expired * 60) == false
                    }
                })
            }
        }
    }
    
    // 本地记录 配置
    public var config: GADConfig? {
        set{
            UserDefaults.standard.setModel(newValue, forKey: .adConfig)
        }
        get {
            UserDefaults.standard.model(GADConfig.self, forKey: .adConfig)
        }
    }
    
    // 本地记录 限制次数
    fileprivate var limit: GADLimit? {
        set{
            UserDefaults.standard.setModel(newValue, forKey: .adLimited)
        }
        get {
            UserDefaults.standard.model(GADLimit.self, forKey: .adLimited)
        }
    }
    
    /// 是否超限
    public var isGADLimited: Bool {
        if limit?.date.isToday == true {
            if (limit?.showTimes ?? 0) >= (config?.showTimes ?? 0) || (limit?.clickTimes ?? 0) >= (config?.clickTimes ?? 0) {
                return true
            }
        }
        return false
    }
        
    /// 广告位加载模型
    let ads:[GADLoadModel] = GADUtil.positions.map { p in
        GADLoadModel(position: p)
    }
}

extension GADUtil {
    
    // 如果使用 async 请求广告 则这个值可能会是错误的。
    public func isLoaded(_ position: GADPosition) -> Bool {
        return self.ads.filter {
            $0.position.rawValue == position.rawValue
        }.first?.isLoadCompletion == true
    }
    
    /// 请求远程配置
    public func requestConfig() {
        // 获取本地配置
        if config == nil {
            let path = Bundle.main.path(forResource: "GADConfig", ofType: "json")
            let url = URL(fileURLWithPath: path!)
            do {
                let data = try Data(contentsOf: url)
                config = try JSONDecoder().decode(GADConfig.self, from: data)
                NSLog("[Config] Read local ad config success.")
            } catch let error {
                NSLog("[Config] Read local ad config fail.\(error.localizedDescription)")
            }
        }
        
        /// 广告配置是否是当天的
        if limit == nil || limit?.date.isToday != true {
            limit = GADLimit(showTimes: 0, clickTimes: 0, date: Date())
        }
    }
    
    /// 限制
    fileprivate func add(_ status: GADLimit.Status) {
        if status == .show {
            if isGADLimited {
                NSLog("[AD] 用戶超限制。")
                GADUtil.positions.forEach {  p in
                    self.clean(p)
                }
                return
            }
            let showTime = limit?.showTimes ?? 0
            limit?.showTimes = showTime + 1
            NSLog("[AD] [LIMIT] showTime: \(showTime+1) total: \(config?.showTimes ?? 0)")
        } else  if status == .click {
            let clickTime = limit?.clickTimes ?? 0
            limit?.clickTimes = clickTime + 1
            NSLog("[AD] [LIMIT] clickTime: \(clickTime+1) total: \(config?.clickTimes ?? 0)")
            if isGADLimited {
                NSLog("[AD] ad limited.")
                GADUtil.positions.forEach {  p in
                    self.clean(p)
                }
                return
            }
        }
    }
    
    /// 加载
    @available(*, renamed: "load()")
    public func load(_ position: GADPosition, completion: ((Bool)->Void)? = nil) {
        let ads = ads.filter{
            $0.position.rawValue == position.rawValue
        }
        ads.first?.beginAddWaterFall(callback: { isSuccess in
            if position.isNative {
                self.show(position) { ad in
                    NotificationCenter.default.post(name: .nativeUpdate, object: ad)
                }
            }
            completion?(isSuccess)
        })
    }
    
    /// 展示
    @available(*, renamed: "show()")
    public func show(_ position: GADPosition, from vc: UIViewController? = nil , completion: ((GADBaseModel?)->Void)? = nil) {
        // 超限需要清空广告
        if isGADLimited {
            GADUtil.positions.forEach {  p in
                self.clean(p)
            }
        }
        let loadAD = ads.filter {
            $0.position.rawValue == position.rawValue
        }.first
        if position.isOpen || position.isInterstital {
            /// 有廣告
            if let ad = loadAD?.loadedArray.first as? GADFullScreenModel, !isGADLimited {
                ad.impressionHandler = { [weak self, loadAD] in
                    loadAD?.impressionDate = Date()
                    self?.add(.show)
                    self?.display(position)
                    if position.isPreload {
                        self?.load(position)
                    }
                }
                ad.clickHandler = { [weak self] in
                    self?.add(.click)
                }
                ad.closeHandler = { [weak self] in
                    self?.disappear(position)
                    completion?(nil)
                }
                ad.present(from: vc)
            } else {
                completion?(nil)
            }
        } else if position.isNative {
            if let ad = loadAD?.loadedArray.first as? GADNativeModel, !isGADLimited {
                /// 预加载回来数据 当时已经有显示数据了
                if loadAD?.isDisplay == true {
                    NSLog("[ad] (\(position.rawValue)) ad is being display.")
                    return
                }
                ad.nativeAd?.unregisterAdView()
                ad.nativeAd?.delegate = ad
                ad.impressionHandler = { [weak loadAD]  in
                    loadAD?.impressionDate = Date()
                    self.add(.show)
                    self.display(position)
                    if position.isPreload {
                        self.load(position)
                    }
                }
                ad.clickHandler = {
                    self.add(.click)
                }
                completion?(ad)
            } else {
                /// 预加载回来数据 当时已经有显示数据了 并且没超过限制
                if loadAD?.isDisplay == true, !isGADLimited {
                    NSLog("[ad] (\(position.rawValue)) preload ad is being display.")
                    return
                }
                completion?(nil)
            }
        }
    }
    
    /// 清除缓存 针对loadedArray数组
    fileprivate func clean(_ position: GADPosition) {
        let loadAD = ads.filter{
            $0.position.rawValue == position.rawValue
        }.first
        loadAD?.clean()
        
        if position.isNative {
            NotificationCenter.default.post(name: .nativeUpdate, object: nil)
        }
    }
    
    /// 关闭正在显示的广告（原生，插屏）针对displayArray
    public func disappear(_ position: GADPosition) {
        
        // 处理 切入后台时候 正好 show 差屏
        let display = ads.filter{
            $0.position.rawValue == position.rawValue
        }.first?.displayArray
        
        if display?.count == 0, position.isInterstital {
            ads.filter{
                $0.position.rawValue == position.rawValue
            }.first?.clean()
        }
        
        ads.filter{
            $0.position.rawValue == position.rawValue
        }.first?.closeDisplay()
        
        if position.isNative {
            NotificationCenter.default.post(name: .nativeUpdate, object: nil)
        }
    }
    
    /// 展示
    fileprivate func display(_ position: any GADPosition) {
        ads.filter {
            $0.position.rawValue == position.rawValue
        }.first?.display()
    }
}

public struct GADConfig: Codable {
    var showTimes: Int?
    var clickTimes: Int?
    var interstitialExpired: Int?
    var openExpired: Int?
    var ads: [GADModels?]?
    
    func arrayWith(_ postion: any GADPosition) -> [GADModel] {
        guard let ads = ads else {
            return []
        }
        
        guard let models = ads.filter({$0?.key == postion.rawValue}).first as? GADModels, let array = models.value   else {
            return []
        }
        
        return array.sorted(by: {$0.theAdPriority > $1.theAdPriority})
    }
    struct GADModels: Codable {
        var key: String
        var value: [GADModel]?
    }
}

public class GADBaseModel: NSObject, Identifiable {
    public let id = UUID().uuidString
    /// 廣告加載完成時間
    var loadedDate: Date?
    
    /// 點擊回調
    var clickHandler: (() -> Void)?
    /// 展示回調
    var impressionHandler: (() -> Void)?
    /// 加載完成回調
    var loadedHandler: ((_ result: Bool, _ error: String) -> Void)?
    
    /// 當前廣告model
    public var model: GADModel?
    /// 廣告位置
    public var position: any GADPosition
    
    // 收入
    public var price: Double = 0.0
    // 收入货币
    public var currency: String = "USD"
    // 广告网络
    public var network: String = ""
    // load ip
    public var loadIP: String = ""
    // impress ip
    public var impressIP: String = ""
    
    init(model: GADModel?, position: any GADPosition) {
        self.model = model
        self.position = position
        super.init()
    }
}

extension GADBaseModel {
    
    @available(*, renamed: "loadAd()")
    @objc public func loadAd( completion: @escaping ((_ result: Bool, _ error: String) -> Void)) {
    }
    
    @available(*, renamed: "present()")
    @objc public func present(from vc: UIViewController? = nil) {
    }
}

public struct GADModel: Codable {
    public var theAdPriority: Int
    public var theAdID: String
}

struct GADLimit: Codable {
    var showTimes: Int
    var clickTimes: Int
    var date: Date
    
    enum Status {
        case show, click
    }
}

//public enum GADPosition: CaseIterable, Equatable {
//    case native
//    case interstitial
//    case open
//}

// 自定义广告位置枚举协议
public protocol GADPosition {
    var isNative: Bool { get }
    var isOpen: Bool {get}
    var isInterstital: Bool { get }
    var rawValue: String { get }
    var isPreload: Bool { get }
    var name: String { get }
}

extension GADPosition {
    var name: String {
        if isNative {
            return "native"
        } else if isInterstital {
            return "interstital"
        } else if isOpen {
            return "open"
        } else {
            return "banner"
        }
    }
}



class GADLoadModel: NSObject {
    /// 當前廣告位置類型
    var position: any GADPosition
    /// 是否正在加載中
    var isPreloadingAD: Bool {
        return loadingArray.count > 0
    }
    // 是否已有加载成功的数据
    var isPreloadedAD: Bool {
        return loadedArray.count > 0
    }
    // 是否加载完成 不管成功还是失败
    var isLoadCompletion: Bool = false
    /// 正在加載術組
    var loadingArray: [GADBaseModel] = []
    /// 加載完成
    var loadedArray: [GADBaseModel] = []
    /// 展示
    var displayArray: [GADBaseModel] = []
        
    var isDisplay: Bool {
        return displayArray.count > 0
    }
    
    /// 该广告位显示广告時間 每次显示更新时间
    var impressionDate = Date(timeIntervalSinceNow: -100)
    
        
    init(position: any GADPosition) {
        self.position = position
        super.init()
    }
}

extension GADLoadModel {
    @available (*, renamed: "beginAddWaterFall()")
    func beginAddWaterFall(callback: ((_ isSuccess: Bool) -> Void)? = nil) {
        isLoadCompletion = false
        if !isPreloadingAD, !isPreloadedAD{
            NSLog("[AD] (\(position.rawValue) start to prepareLoad.--------------------")
            if let array: [GADModel] = GADUtil.share.config?.arrayWith(position), array.count > 0 {
                NSLog("[AD] (\(position.rawValue)) start to load array = \(array.count)")
                prepareLoadAd(array: array) { [weak self] isSuccess in
                    self?.isLoadCompletion = true
                    callback?(isSuccess)
                }
            } else {
                NSLog("[AD] (\(position.rawValue)) no configer.")
            }
        } else if isPreloadedAD {
            isLoadCompletion = true
            callback?(true)
            NSLog("[AD] (\(position.rawValue)) loaded ad.")
        } else if isPreloadingAD {
            NSLog("[AD] (\(position.rawValue)) loading ad.")
        }
    }
    
    func prepareLoadAd(array: [GADModel], at index: Int = 0, callback: ((_ isSuccess: Bool) -> Void)?) {
        if  index >= array.count {
            NSLog("[AD] (\(position.rawValue)) prepare Load Ad Failed, no more avaliable config.")
            return
        }
        NSLog("[AD] (\(position)) prepareLoaded.")
        if GADUtil.share.isGADLimited {
            NSLog("[AD] (\(position.rawValue)) load limit")
            callback?(false)
            return
        }
        if isPreloadedAD {
            NSLog("[AD] (\(position.rawValue)) load completion。")
            callback?(false)
            return
        }
        if isPreloadingAD {
            NSLog("[AD] (\(position.rawValue)) loading ad.")
            callback?(false)
            return
        }
        
        var ad: GADBaseModel? = nil
        if position.isNative {
            ad = GADNativeModel(model: array[index], position: position)
        } else if position.isOpen {
            ad = GADOpenModel(model: array[index], position: position)
        } else if position.isInterstital {
            ad = GADInterstitialModel(model: array[index], position: position)
        }
        guard let ad = ad  else {
            NSLog("[AD] (\(position.rawValue)) posion error.")
            callback?(false)
            return
        }
        ad.position = position
        ad.loadAd { [weak ad] isSuccess, error in
            guard let ad = ad else { return }
            /// 刪除loading 中的ad
            self.loadingArray = self.loadingArray.filter({ loadingAd in
                return ad.id != loadingAd.id
            })
            
            /// 成功
            if isSuccess {
                self.loadedArray.append(ad)
                callback?(true)
                return
            }
            
            NSLog("[AD] (\(self.position)) Load Ad Failed: try reload at index: \(index + 1).")
            self.prepareLoadAd(array: array, at: index + 1, callback: callback)
        }
        loadingArray.append(ad)
    }
    
    fileprivate func display() {
        self.displayArray = self.loadedArray
        self.loadedArray = []
    }
    
    fileprivate func closeDisplay() {
        self.displayArray = []
    }
    
    fileprivate func clean() {
        self.displayArray = []
        self.loadedArray = []
        self.loadingArray = []
    }
}

extension Date {
    func isExpired(with time: Double) -> Bool {
        Date().timeIntervalSince1970 - self.timeIntervalSince1970 > time
    }
    
    var isToday: Bool {
        let diff = Calendar.current.dateComponents([.day], from: self, to: Date())
        if diff.day == 0 {
            return true
        } else {
            return false
        }
    }
}

class GADFullScreenModel: GADBaseModel {
    /// 關閉回調
    var closeHandler: (() -> Void)?
    var autoCloseHandler: (()->Void)?
    /// 異常回調 點擊了兩次
    var clickTwiceHandler: (() -> Void)?
    
    /// 是否點擊過，用於拉黑用戶
    var isClicked: Bool = false
        
    deinit {
        NSLog("[Memory] (\(position.rawValue)) \(self) 💧💧💧.")
    }
}

class GADInterstitialModel: GADFullScreenModel {
    /// 插屏廣告
    var ad: GADInterstitialAd?
}

extension GADInterstitialModel: GADFullScreenContentDelegate {
    public override func loadAd(completion: ((_ result: Bool, _ error: String) -> Void)?) {
        loadedHandler = completion
        loadedDate = nil
        GADInterstitialAd.load(withAdUnitID: model?.theAdID ?? "", request: GADRequest()) { [weak self] ad, error in
            guard let self = self else { return }
            if let error = error {
                NSLog("[AD] (\(self.position)) load ad FAILED for id \(self.model?.theAdID ?? "invalid id")")
                self.loadedHandler?(false, error.localizedDescription)
                return
            }
            NSLog("[AD] (\(self.position)) load ad SUCCESSFUL for id \(self.model?.theAdID ?? "invalid id") ✅✅✅✅")
            self.ad = ad
            self.ad?.paidEventHandler = { adValue in
                self.price = Double(truncating: adValue.value)
                self.currency = adValue.currencyCode
            }
            self.network = self.ad?.responseInfo.loadedAdNetworkResponseInfo?.adNetworkClassName ?? ""
            self.ad?.fullScreenContentDelegate = self
            self.loadedDate = Date()
            self.loadedHandler?(true, "")
        }
    }
    
    override func present(from vc: UIViewController? = nil) {
        Task.detached { @MainActor in
            if let vc = vc {
                self.ad?.present(fromRootViewController: vc)
            } else if let keyWindow = (UIApplication.shared.connectedScenes.filter({$0 is UIWindowScene}).first as? UIWindowScene)?.keyWindow, let rootVC = keyWindow.rootViewController {
                if let pc = rootVC.presentedViewController {
                    self.ad?.present(fromRootViewController: pc)
                } else {
                    self.ad?.present(fromRootViewController: rootVC)
                }
            }
        }
    }
    
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        loadedDate = Date()
        impressionHandler?()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        NSLog("[AD] (\(self.position)) didFailToPresentFullScreenContentWithError ad FAILED for id \(self.model?.theAdID ?? "invalid id")")
        closeHandler?()
    }
    
    func adWillDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        closeHandler?()
    }
    
    func adDidRecordClick(_ ad: GADFullScreenPresentingAd) {
        clickHandler?()
    }
}

class GADOpenModel: GADFullScreenModel {
    /// 插屏廣告
    var ad: GADAppOpenAd?
}

extension GADOpenModel: GADFullScreenContentDelegate {
    override func loadAd(completion: ((_ result: Bool, _ error: String) -> Void)?) {
        loadedHandler = completion
        loadedDate = nil
        GADAppOpenAd.load(withAdUnitID: model?.theAdID ?? "", request: GADRequest()) { [weak self] ad, error in
            guard let self = self else { return }
            if let error = error {
                NSLog("[AD] (\(self.position)) load ad FAILED for id \(self.model?.theAdID ?? "invalid id")")
                self.loadedHandler?(false, error.localizedDescription)
                return
            }
            self.ad = ad
            self.ad?.paidEventHandler = { adValue in
                self.price = Double(truncating: adValue.value)
                self.currency = adValue.currencyCode
            }
            self.network = self.ad?.responseInfo.loadedAdNetworkResponseInfo?.adNetworkClassName ?? ""
            NSLog("[AD] (\(self.position)) load ad SUCCESSFUL for id \(self.model?.theAdID ?? "invalid id") ✅✅✅✅")
            self.ad?.fullScreenContentDelegate = self
            self.loadedDate = Date()
            self.loadedHandler?(true, "")
        }
    }
    
    override func present(from vc: UIViewController? = nil) {
        Task.detached { @MainActor in
            if let vc = vc {
                self.ad?.present(fromRootViewController: vc)
            } else if let keyWindow = (UIApplication.shared.connectedScenes.filter({$0 is UIWindowScene}).first as? UIWindowScene)?.keyWindow, let rootVC = keyWindow.rootViewController {
                if let pc = rootVC.presentedViewController {
                    self.ad?.present(fromRootViewController: pc)
                } else {
                    self.ad?.present(fromRootViewController: rootVC)
                }
            }
        }
    }
    
    func adDidRecordImpression(_ ad: GADFullScreenPresentingAd) {
        loadedDate = Date()
        impressionHandler?()
    }
    
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        NSLog("[AD] (\(self.position)) didFailToPresentFullScreenContentWithError ad FAILED for id \(self.model?.theAdID ?? "invalid id")")
        closeHandler?()
    }
    
    func adWillDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        closeHandler?()
    }
    
    func adDidRecordClick(_ ad: GADFullScreenPresentingAd) {
        clickHandler?()
    }
}

public class GADNativeModel: GADBaseModel {
    /// 廣告加載器
    var loader: GADAdLoader?
    /// 原生廣告
    public var nativeAd: GADNativeAd?
    
    deinit {
        NSLog("[Memory] (\(position.rawValue)) \(self) 💧💧💧.")
    }
}

extension GADNativeModel {
    
    public override func loadAd(completion: ((_ result: Bool, _ error: String) -> Void)?) {
        loadedDate = nil
        loadedHandler = completion
        loader = GADAdLoader(adUnitID: model?.theAdID ?? "", rootViewController: nil, adTypes: [.native], options: nil)
        loader?.delegate = self
        loader?.load(GADRequest())
    }
    
    public func unregisterAdView() {
        nativeAd?.unregisterAdView()
    }
}

extension GADNativeModel: GADAdLoaderDelegate {
    public func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        NSLog("[AD] (\(position.rawValue)) load ad FAILED for id \(model?.theAdID ?? "invalid id")")
        loadedHandler?(false, error.localizedDescription)
    }
}

extension GADNativeModel: GADNativeAdLoaderDelegate {
    public func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        NSLog("[AD] (\(position.rawValue)) load ad SUCCESSFUL for id \(model?.theAdID ?? "invalid id") ✅✅✅✅")
        self.nativeAd = nativeAd
        self.nativeAd?.paidEventHandler = { adValue in
            self.price = Double(truncating: adValue.value)
            self.currency = adValue.currencyCode
        }
        self.network = self.nativeAd?.responseInfo.loadedAdNetworkResponseInfo?.adNetworkClassName ?? ""
        loadedDate = Date()
        loadedHandler?(true, "")
    }
}

extension GADNativeModel: GADNativeAdDelegate {
    public func nativeAdDidRecordClick(_ nativeAd: GADNativeAd) {
        clickHandler?()
    }
    
    public func nativeAdDidRecordImpression(_ nativeAd: GADNativeAd) {
        impressionHandler?()
    }
    
    public func nativeAdWillPresentScreen(_ nativeAd: GADNativeAd) {
    }
}


extension UserDefaults {
    public func setModel<T: Encodable> (_ object: T?, forKey key: String) {
        let encoder =  JSONEncoder()
        guard let object = object else {
            self.removeObject(forKey: key)
            return
        }
        guard let encoded = try? encoder.encode(object) else {
            return
        }
        
        self.setValue(encoded, forKey: key)
    }
    
    public func model<T: Decodable> (_ type: T.Type, forKey key: String) -> T? {
        guard let data = self.data(forKey: key) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let object = try? decoder.decode(type, from: data) else {
            print("Could'n find key")
            return nil
        }
        
        return object
    }
}

extension Notification.Name {
    public static let nativeUpdate = Notification.Name(rawValue: "homeNativeUpdate")
}

extension String {
    static let adConfig = "adConfig"
    static let adLimited = "adLimited"
}
