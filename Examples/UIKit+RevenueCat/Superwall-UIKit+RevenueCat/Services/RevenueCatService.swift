//
//  RevenueCatService.swift
//  Superwall-UIKit+RevenueCat
//
//  Created by Yusuf Tör on 01/11/2022.
//

import SwiftUI
import RevenueCat
import StoreKit

final class RevenueCatService {
  static let shared = RevenueCatService()
  @Published var isSubscribed = false

  static func initPurchases() {
    // Make sure to set usesStoreKit2IfAvailable to false
    // if purchasing a product directly.
    Purchases.configure(
      with: .init(withAPIKey: "appl_XmYQBWbTAFiwLeWrBJOeeJJtTql")
        .with(appUserID: "abc")
        .with(usesStoreKit2IfAvailable: false)
    )
  }

  static func restorePurchases() async -> Bool {
    do {
      let customerInfo = try await Purchases.shared.restorePurchases()
      return customerInfo.entitlements.active["pro"] != nil
    } catch {
      return false
    }
  }

  func purchase(_ product: SKProduct) async throws -> Bool {
    let storeProduct = StoreProduct(sk1Product: product)
    let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(product: storeProduct)
    let isSubscribed = customerInfo.entitlements.active["pro"] != nil
    self.isSubscribed = isSubscribed
    return userCancelled
  }

  func updateSubscriptionStatus() async {
    do {
      let customerInfo = try await Purchases.shared.customerInfo()
      isSubscribed = customerInfo.entitlements.active["pro"] != nil
    } catch {
      print("Couldn't get customer info", error)
    }
  }
}
