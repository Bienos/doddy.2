import DoddyCore
import SwiftUI

/// What Open Food Facts says a scanned barcode is (Shopping list+, ADR-631). Nothing goes on the
/// list until the tap on Add; Cancel leaves the list as it was.
struct BarcodeProductSheet: View {
    let product: OpenFoodFactsProduct
    let listName: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: product.name)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let brand = product.brand {
                    Text(verbatim: brand).foregroundStyle(Theme.secondaryText)
                }
                if let quantity = product.quantity {
                    Text(verbatim: quantity).foregroundStyle(Theme.secondaryText)
                }
                Text(String(format: NSLocalizedString("It goes on “%@” as: %@", comment: ""), listName, product.itemText))
                    .font(.subheadline)
                Text("Product data from Open Food Facts (ODbL). Only the barcode number was sent to them; the photo stayed on this iPhone and wasn't kept.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
                Button {
                    onAdd()
                    dismiss()
                } label: {
                    Text(String(format: NSLocalizedString("Add to “%@”", comment: ""), listName))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .accessibilityIdentifier("barcode.add")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.canvas)
            .foregroundStyle(Theme.ink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One answer to show; a new identity each time, so the same product scanned twice shows again.
struct BarcodeScan: Identifiable {
    let id = UUID()
    let product: OpenFoodFactsProduct
}
