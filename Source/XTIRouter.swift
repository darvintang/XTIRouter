//
//  XTIRouter.swift
//
//  Created by xtinput on 2021/4/20.
//

import ObjectiveC
import UIKit

/// 该协议继承无效，A实现了该协议，B继承A，只能路由到A。如果A、B有相同的业务请将相同的业务放到C，然后A和B实现该协议
@objc public protocol XTIRouterProtocol {
    static func deploy(_ parameter: String, _ dict: [String: Any]) -> Self?
    static var keyPath: String { get }
    @objc func handle(_ completion: ((Any?) -> Void)?)
}

/// 路由管理类
public struct XTIRouter {
    /// 项目的scheme，在项目启动完成之前修改
    public static var scheme: String = "router"

    fileprivate static var routerClassList: [AnyClass]?

    fileprivate static var _routerClassDict: [String: XTIRouterProtocol.Type] = [:]
    fileprivate static var routerClassDict: [String: XTIRouterProtocol.Type] {
        if routerClassList == nil {
            routerClassList = getClassesImplementingProtocol(XTIRouterProtocol.self)
            routerClassList?.forEach({ cls in
                if let tcls = cls as? XTIRouterProtocol.Type {
                    let keyPath = tcls.keyPath
                    let key = "\(keyPath)"
                    assert(routerClassDict[key] == nil, "类\(tcls.self)和类\(routerClassDict[key].self!)的keyPath冲突")
                    assert(keyPath.count > 0, "类\(tcls.self)的keyPath不能为空字符串")
                    _routerClassDict["\(keyPath)"] = tcls
                }
            })
        }
        return _routerClassDict
    }

    public static func printDebugRouter() {
        print(self.routerClassDict)
    }

    fileprivate static func currentViewController(_ vc: UIViewController?) -> UIViewController? {
        guard let tempVC = vc else {
            return vc
        }
        if let presentVC = tempVC.presentedViewController {
            return self.currentViewController(presentVC)
        }

        if let navVC = tempVC as? UINavigationController {
            return self.currentViewController(navVC.visibleViewController)
        }
        if let tabbarVC = tempVC as? UITabBarController {
            return self.currentViewController(tabbarVC.selectedViewController)
        }

        return vc
    }

    public static var currentVC: UIViewController? {
        var window = UIApplication.shared.keyWindow
        if window?.windowLevel != UIWindow.Level.normal {
            let windows = UIApplication.shared.windows
            for windowTemp in windows {
                if windowTemp.windowLevel == UIWindow.Level.normal {
                    window = windowTemp
                    break
                }
            }
        }
        let vc = window?.rootViewController
        return currentViewController(vc)
    }

    public static var filter: ((String) -> String) = { $0 }
    /// 通过一个路由url进行界面跳转或处理
    /// - Parameters:
    ///   - urlString: 跳转的链接，scheme://keyPath?parameter，scheme为空会忽略不进行匹配
    ///   - dict: 附加参数，比如在哪个对象调用，处理后的闭包等等
    ///   - isExecute: 是否需要立刻执行，默认需要。即立刻执行handle方法，如果不需要那么不会调用handle方法
    ///   - completion: 处理完成的闭包
    /// - Returns:通过路由初始化后得到的对象。handle方法在主线程执行，对象返回不代表handle执行完毕
    @discardableResult public static func send(_ urlString: String, dict: [String: Any]? = nil, isExecute: Bool = true, completion: ((Any) -> Void)? = nil) -> XTIRouterProtocol? {
        guard let url = URL(string: self.filter(urlString)) else {
            return nil
        }
        if url.scheme == self.scheme || url.scheme == nil {
            let key = (url.host?.isEmpty ?? true) ? url.path : (url.host! + (url.path.isEmpty ? "" : "/" + url.path))

            let toObj = self.routerClassDict[key]?.deploy(url.query ?? "", dict ?? [:])
            if isExecute {
                DispatchQueue.main.async {
                    toObj?.handle(completion)
                }
            }
            return toObj
        }
        return nil
    }

    /// 获取实现了协议的所有的类
    /// - Parameter p:协议
    /// - Returns:实现了协议的所有的类列表
    fileprivate static func getClassesImplementingProtocol(_ p: Protocol) -> [AnyClass] {
        let classes = self.objc_getClassList()
        var ret = [AnyClass]()
        for cls in classes {
            if class_conformsToProtocol(cls, p) {
                ret.append(cls)
            }
        }

        return ret
    }

    /// 获取项目里的所有的类
    /// - Returns: 所有的类列表
    fileprivate static func objc_getClassList() -> [AnyClass] {
        let expectedClassCount = ObjectiveC.objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(expectedClassCount))
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualClassCount: Int32 = ObjectiveC.objc_getClassList(autoreleasingAllClasses, expectedClassCount)

        var classes = [AnyClass]()
        for i in 0 ..< actualClassCount {
            if let currentClass = allClasses[Int(i)] {
                classes.append(currentClass)
            }
        }
        allClasses.deallocate()
        return classes
    }

    // 拦截应用的openURL
    public static var permitOpenURL: ((_ url: URL, _ options: [UIApplication.OpenExternalURLOptionsKey: Any]?, _ completion: ((Bool) -> Void)?) -> Bool)? {
        willSet {
            assert(permitOpenURL == nil, "permitOpenURL不能重复设置")
            UIApplication.xtihook()
        }
    }
}

fileprivate extension UIApplication {
    fileprivate static func xtihook() {
        let originClass = UIApplication.classForCoder()
        let originSelector = Selector("openURL:options:completionHandler:")
        let swizzledSelector = Selector("xti_open:options:completionHandler:")

        let originMethod = ObjectiveC.class_getInstanceMethod(originClass, originSelector)
        let swizzledMethod = ObjectiveC.class_getInstanceMethod(originClass, swizzledSelector)
        if originMethod != nil && swizzledMethod != nil {
            if ObjectiveC.class_addMethod(originClass, originSelector, method_getImplementation(swizzledMethod!), method_getTypeEncoding(swizzledMethod!)) {
                ObjectiveC.class_replaceMethod(originClass, swizzledSelector, method_getImplementation(originMethod!), method_getTypeEncoding(originMethod!))
            } else {
                ObjectiveC.method_exchangeImplementations(originMethod!, swizzledMethod!)
            }
        }
    }

    @objc fileprivate func xti_open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: ((Bool) -> Void)? = nil) {
        if XTIRouter.permitOpenURL?(url, options, completion) ?? true {
            self.xti_open(url, options: options, completionHandler: completion)
        }
    }
}
