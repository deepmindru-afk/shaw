//
//  PaywallView.swift
//  Roadtrip
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @SwiftUI.Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: Product?
    @State private var purchaseError: String?
    @State private var showError = false

    private var weeklyBaselinePrice: Decimal? {
        subscriptionManager.availableProducts
            .first(where: { $0.id.lowercased().contains("week") })?
            .weeklyPriceValue
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.blue)

                        Text("Upgrade to Roadtrip Pro")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Unlimited voice AI conversations")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 32)

                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "infinity", text: "Unlimited minutes per month")
                        FeatureRow(icon: "icloud", text: "Sync across all your devices")
                        FeatureRow(icon: "doc.text", text: "Session summaries & transcripts")
                        FeatureRow(icon: "waveform", text: "Premium voice options")
                    }
                    .padding(.horizontal)

                    // Products
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .padding()
                    } else if subscriptionManager.availableProducts.isEmpty {
                        Text("Loading subscription options...")
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(subscriptionManager.availableProducts, id: \.id) { product in
                                ProductButton(
                                    product: product,
                                    isSelected: selectedProduct?.id == product.id,
                                    weeklyBaselinePrice: weeklyBaselinePrice,
                                    onTap: {
                                        selectedProduct = product
                                        purchaseProduct(product)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Restore button
                    Button(action: restore) {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(.top, 8)

                    // Legal footer
                    VStack(spacing: 8) {
                        HStack(spacing: 16) {
                            Button("Terms of Service") {
                                openURL("https://roadtrip.ai/terms")
                            }
                            .font(.caption)

                            Button("Privacy Policy") {
                                openURL("https://roadtrip.ai/privacy")
                            }
                            .font(.caption)
                        }

                        Text("Subscriptions auto-renew unless cancelled. Cancel anytime in App Store settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = purchaseError {
                    Text(error)
                }
            }
        }
        .task {
            await subscriptionManager.loadProducts()
        }
    }

    private func purchaseProduct(_ product: Product) {
        Task {
            do {
                try await subscriptionManager.purchase(product: product)
                dismiss()
            } catch let error as SubscriptionError {
                purchaseError = error.errorDescription
                showError = true
            } catch {
                purchaseError = "An unexpected error occurred: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func restore() {
        Task {
            do {
                try await subscriptionManager.restore()
                dismiss()
            } catch {
                purchaseError = "No previous purchases found."
                showError = true
            }
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            Text(text)
                .font(.body)

            Spacer()
        }
    }
}

struct ProductButton: View {
    let product: Product
    let isSelected: Bool
    let weeklyBaselinePrice: Decimal?
    let onTap: () -> Void

    private var savings: String? {
        guard
            let baseline = weeklyBaselinePrice,
            baseline > .zero,
            let productWeeklyPrice = product.weeklyPriceValue,
            productWeeklyPrice < baseline
        else {
            return nil
        }

        let savingsPercentage = ((baseline - productWeeklyPrice) / baseline) * 100
        let percentageValue = NSDecimalNumber(decimal: savingsPercentage).doubleValue
        let roundedPercentage = Int(percentageValue.rounded())

        guard roundedPercentage >= 1 else { return nil }
        return "Save \(roundedPercentage)%"
    }

    private var period: String {
        product.paywallPeriodLabel
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(period)
                            .font(.headline)

                        if let savings = savings {
                            Text(savings)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }

                    Text(product.displayPrice)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
}

private extension Product {
    var paywallPeriodLabel: String {
        let lowercasedId = id.lowercased()
        if lowercasedId.contains("week") { return "Weekly" }
        if lowercasedId.contains("month") { return "Monthly" }
        if lowercasedId.contains("year") { return "Yearly" }

        if let subscriptionInfo = subscription {
            return subscriptionInfo.subscriptionPeriod.defaultLabel
        }

        return "Subscription"
    }

    var weeklyPriceValue: Decimal? {
        guard let subscriptionInfo = subscription else {
            return nil
        }

        let subscriptionPeriod = subscriptionInfo.subscriptionPeriod

        guard
            let weeks = subscriptionPeriod.approximateWeeks,
            weeks > .zero
        else {
            return nil
        }
        return price / weeks
    }
}

private extension Product.SubscriptionPeriod {
    var defaultLabel: String {
        switch unit {
        case .day:
            if value == 1 { return "Daily" }
            if value % 7 == 0 {
                let weeks = value / 7
                return weeks == 1 ? "Weekly" : "\(weeks)-Week"
            }
            return "\(value)-Day"
        case .week:
            return value == 1 ? "Weekly" : "\(value)-Week"
        case .month:
            return value == 1 ? "Monthly" : "\(value)-Month"
        case .year:
            return value == 1 ? "Yearly" : "\(value)-Year"
        @unknown default:
            return "Subscription"
        }
    }

    var approximateWeeks: Decimal? {
        switch unit {
        case .day:
            return Decimal(value) / Decimal(7)
        case .week:
            return Decimal(value)
        case .month:
            return Decimal(value) * PaywallPeriodMath.weeksPerMonth
        case .year:
            return Decimal(value) * PaywallPeriodMath.weeksPerYear
        @unknown default:
            return nil
        }
    }
}

private enum PaywallPeriodMath {
    static let weeksPerYear = Decimal(52)
    static let weeksPerMonth = weeksPerYear / Decimal(12)
}
