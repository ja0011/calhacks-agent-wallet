//
//  OnrampCheckoutView.swift
//  Agentwallet
//

import SwiftUI
import CrossmintCheckout

/// Crossmint's embedded checkout for an onramp order created by our server.
/// The environment comes from the client key: a `ck_staging_` key selects staging.
struct OnrampCheckoutView: View {
    let session: OnrampViewModel.CheckoutSession
    let onOrderUpdated: (_ phase: String?, _ paymentStatus: String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CrossmintEmbeddedCheckout(
                apiKey: session.clientApiKey,
                orderId: session.orderId,
                clientSecret: session.clientSecret,
                payment: CheckoutPayment(
                    crypto: CheckoutCryptoPayment(enabled: false),
                    fiat: CheckoutFiatPayment(
                        enabled: true,
                        allowedMethods: CheckoutAllowedMethods(googlePay: false, applePay: false, card: true)
                    )
                ),
                appearance: CheckoutAppearance(
                    rules: CheckoutAppearanceRules(
                        // The server already set the recipient wallet and receipt email.
                        destinationInput: CheckoutDestinationInputRule(isHidden: true),
                        receiptEmailInput: CheckoutReceiptEmailInputRule(isHidden: true)
                    )
                )
            )
            .onOrderUpdated { update in
                onOrderUpdated(update.order?.phase?.rawValue, update.order?.payment?.status)
            }
            .navigationTitle("Add $\(OnrampViewModel.amount) USDC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
