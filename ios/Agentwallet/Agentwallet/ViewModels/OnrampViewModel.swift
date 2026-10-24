//
//  OnrampViewModel.swift
//  Agentwallet
//

import Foundation
import Observation

/// "Add money" flow: create a Crossmint onramp order on our server, show Crossmint's
/// embedded checkout, then poll the server until the USDC is delivered.
@Observable
final class OnrampViewModel {
    /// What the embedded checkout needs. Non-nil while the checkout sheet is shown.
    struct CheckoutSession: Identifiable {
        let orderId: String
        let clientSecret: String
        /// Publishable Crossmint client key from GET /api/onramp/config.
        let clientApiKey: String
        var id: String { orderId }
    }

    enum Status: Equatable {
        case idle
        case preparing
        case inCheckout
        case waitingForDelivery(String)
        case delivered(txId: String?)
        case failed(String)
    }

    static let amount = "5"
    private static let pollInterval: Duration = .seconds(3)
    private static let maxPolls = 60

    var session: CheckoutSession?
    private(set) var status: Status = .idle
    /// Set once the checkout reports the payment went through.
    private var checkoutFinished = false
    private var orderId: String?

    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    var isBusy: Bool {
        switch status {
        case .preparing, .inCheckout, .waitingForDelivery: true
        default: false
        }
    }

    func start() async {
        guard !isBusy else { return }
        status = .preparing
        checkoutFinished = false

        // Linking is idempotent on Crossmint's side; if it fails because the wallet is
        // already linked, the order below still works, so its result is ignored.
        try? await client.linkOnrampWallet()

        do {
            let order = try await client.createOnrampOrder(amount: Self.amount)
            let config = try await client.fetchOnrampConfig()
            guard config.environment == "staging" else {
                status = .failed("Expected the staging environment, got \(config.environment).")
                return
            }
            orderId = order.orderId
            session = CheckoutSession(
                orderId: order.orderId,
                clientSecret: order.clientSecret,
                clientApiKey: config.clientApiKey
            )
            status = .inCheckout
        } catch {
            status = .failed("Couldn't start checkout: \(error.localizedDescription)")
        }
    }

    /// Called for each order update from the checkout. Once the order reaches the
    /// delivery or completed phase, the payment is done and the sheet can close.
    func checkoutUpdated(phase: String?, paymentStatus: String?) {
        if phase == "delivery" || phase == "completed" || paymentStatus == "completed" {
            checkoutFinished = true
            session = nil
        }
    }

    /// Called when the checkout sheet closes, either by the user or after payment.
    func checkoutClosed(wallet: ChatViewModel) async {
        guard let orderId else { return }
        if checkoutFinished {
            await pollUntilDelivered(orderId: orderId)
        } else {
            await showCurrentStatus(orderId: orderId)
        }
        await wallet.refreshWallet()
    }

    private func pollUntilDelivered(orderId: String) async {
        status = .waitingForDelivery("Payment received. Waiting for USDC…")
        for _ in 0..<Self.maxPolls {
            do {
                let order = try await client.fetchOnrampOrderStatus(orderId: orderId)
                if order.deliveryStatus == "completed" {
                    status = .delivered(txId: order.txId)
                    return
                }
                if order.deliveryStatus == "failed" || order.paymentStatus?.hasPrefix("failed") == true {
                    status = .failed("Order failed (payment: \(order.paymentStatus ?? "?"), delivery: \(order.deliveryStatus ?? "?")).")
                    return
                }
                status = .waitingForDelivery(
                    "Payment: \(order.paymentStatus ?? "?"), delivery: \(order.deliveryStatus ?? "?")"
                )
            } catch {
                status = .failed("Couldn't check the order: \(error.localizedDescription)")
                return
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
        status = .failed("USDC hasn't arrived yet. Check again later.")
    }

    /// The user closed the checkout before paying: show where the order stands.
    private func showCurrentStatus(orderId: String) async {
        do {
            let order = try await client.fetchOnrampOrderStatus(orderId: orderId)
            if order.deliveryStatus == "completed" {
                status = .delivered(txId: order.txId)
            } else if order.paymentStatus == "in-progress" || order.paymentStatus == "completed" {
                await pollUntilDelivered(orderId: orderId)
            } else {
                status = .failed("Checkout closed. Payment status: \(order.paymentStatus ?? "unknown").")
            }
        } catch {
            status = .failed("Couldn't check the order: \(error.localizedDescription)")
        }
    }
}
