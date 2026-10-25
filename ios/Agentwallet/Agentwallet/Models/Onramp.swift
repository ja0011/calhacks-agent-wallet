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

    var items: [CatalogItem]? = nil
    var vault: TimeVault? = nil
    let walletAddress: String?
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

enum WalletAddressDisplay {
    static func shortened(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return String(address.prefix(6)) + "…" + String(address.suffix(4))
    }

    static func explorerURL(_ address: String) -> URL? {
        guard address.count == 42, address.hasPrefix("0x"),
              address.dropFirst(2).allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return URL(string: "https://sepolia.basescan.org/address/")?.appendingPathComponent(address)
    }
}

struct TimeVault: Codable {
    let lockedTotal: String?
    let entries: [Entry]

    struct Entry: Codable, Identifiable {
        var id = UUID()
        let amount: String
        let lockedAt: String
        let releasesAt: String
        let daysLeft: Int

        private enum CodingKeys: String, CodingKey {
            case amount, lockedAt, releasesAt, daysLeft
        }

        static func displayDate(_ value: String) -> String {
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            let standard = Date.ISO8601FormatStyle()
            guard let date = (try? fractional.parse(value)) ?? (try? standard.parse(value)) else {
                return "Date unavailable"
            }
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
