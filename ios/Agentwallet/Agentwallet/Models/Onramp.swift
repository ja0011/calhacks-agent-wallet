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

/// Response body for GET /api/wallet.
struct WalletResponse: Codable {
    let balance: String
    let purchases: [Purchase]
}
