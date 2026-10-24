//
//  Onramp.swift
//  Agentwallet
//

import Foundation

/// Request body for POST /api/onramp/order.
struct OnrampOrderRequest: Codable {
    let amount: String
}

/// Response body for POST /api/onramp/order.
struct OnrampOrder: Codable {
    let orderId: String
    let clientSecret: String
    let paymentStatus: String?
}

/// Response body for GET /api/onramp/config. The client key is publishable.
struct OnrampConfig: Codable {
    let clientApiKey: String
    let environment: String
}

/// Response body for GET /api/onramp/order/:orderId.
struct OnrampOrderStatus: Codable {
    let paymentStatus: String?
    let deliveryStatus: String?
    let txId: String?
}

/// Response body for GET /api/wallet. `balance` is null when the server can't read the chain;
/// `bank` and `activity` are optional fields the server may add.
struct WalletResponse: Codable {
    struct Bank: Codable {
        let balance: String?
    }

    struct Limits: Codable {
        let perPaymentText: String
        let perSessionText: String
    }

    let unlockPriceText: String
    let limits: Limits
    let balance: String?
    let bank: Bank?
    let activity: [ActivityItem]?
    let purchases: [Purchase]
}

 /// Balance fields returned by a successful unlock; other wallet metadata is optional.
struct UnlockResponse: Decodable {
    let balance: String?
    let bank: WalletResponse.Bank?
    let activity: [ActivityItem]?
}
