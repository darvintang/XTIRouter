//
//  XTIRouter.swift
//
//  Created by xtinput on 2021/4/20.
//

import Foundation
import ObjectiveC

/// 该协议继承无效，A实现了该协议，B继承A，只能路由到A。如果A、B有相同的业务请将相同的业务放到C，然后A和B实现该协议
@objc public protocol XTIRouterProtocol {
    static func deploy(_ parameter: String, _ dict: [String: Any]) -> Self?
    static var keyPath: String { get }
    @objc optional func handle()
}

/// 路由管理类
public struct XTIRouterManager {
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
                    let key = "\(scheme)://\(keyPath)"
                    assert(routerClassDict[key] == nil, "类\(tcls.self)和类\(routerClassDict[key].self!)的keyPath冲突")
                    assert(keyPath.count > 0, "类\(tcls.self)的keyPath不能为空字符串")
                    _routerClassDict["\(scheme)://\(keyPath)"] = tcls
                }
            })
        }
        return _routerClassDict
    }

    public static func printDebugRouter() {
        print(routerClassDict)
    }

    /// 通过一个路由url进行界面跳转或处理
    /// - Parameters:
    ///   - urlString: 跳转的链接，scheme://keyPath?Parameter
    ///   - dict: 附加参数，比如在哪个对象调用，处理后的闭包等等
    ///   - isExecute: 是否需要立刻执行，默认需要。即立刻执行handle方法，如果不需要那么不会调用handle方法
    /// - Returns:通过路由初始化后得到的对象。handle方法在主线程执行，对象返回不代表handle执行完毕
    @discardableResult public static func to(_ urlString: String, dict: [String: Any]? = nil, isExecute: Bool = true) -> XTIRouterProtocol? {
        let tempList = urlString.components(separatedBy: "?")

        if let key = tempList.first {
            let toObj = routerClassDict[key]?.deploy(tempList.count == 2 ? tempList.last! : "", dict ?? [:])
            if isExecute {
                DispatchQueue.main.async {
                    toObj?.handle?()
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
        let classes = objc_getClassList()
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
            if let currentClass: AnyClass = allClasses[Int(i)] {
                classes.append(currentClass)
            }
        }
        allClasses.deallocate()
        return classes
    }
}
