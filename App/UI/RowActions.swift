import SwiftUI

// Acties op een rij in een `List`: swipe en contextmenu geven dezelfde acties (een gebaar is altijd ook zichtbaar).
// Verwijderen staat bij swipen vooraan (rood, aan de rand) en in het contextmenu als laatste.

/// Een extra actie op een rij, naast Bewerken en Verwijderen.
struct RowAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var role: ButtonRole? = nil
    var tint: Color? = nil
    let action: () -> Void

    init(_ title: String, symbol: String, role: ButtonRole? = nil, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.tint = tint
        self.action = action
    }
}

private struct RowActionsModifier: ViewModifier {
    let edit: (() -> Void)?
    let delete: (() -> Void)?
    let extra: [RowAction]

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let delete {
                    Button(role: .destructive, action: delete) {
                        Label("Verwijderen", systemImage: "trash")
                    }
                }
                if let edit {
                    Button(action: edit) {
                        Label("Bewerken", systemImage: "pencil")
                    }
                }
                ForEach(extra) { item in
                    Button(role: item.role, action: item.action) {
                        Label(item.title, systemImage: item.symbol)
                    }
                    .tint(item.tint)
                }
            }
            .contextMenu {
                if let edit {
                    Button(action: edit) {
                        Label("Bewerken", systemImage: "pencil")
                    }
                }
                ForEach(extra) { item in
                    Button(role: item.role, action: item.action) {
                        Label(item.title, systemImage: item.symbol)
                    }
                }
                if let delete {
                    Button(role: .destructive, action: delete) {
                        Label("Verwijderen", systemImage: "trash")
                    }
                }
            }
    }
}

extension View {
    /// Swipe-acties en contextmenu voor een rij in een `List`: Verwijderen (rood), Bewerken en eventueel extra acties.
    /// Een verwijdering die een bevestiging vraagt, zet daar in `delete` de bevestiging aan; deze modifier vraagt niets zelf.
    func rowActions(edit: (() -> Void)? = nil, delete: (() -> Void)? = nil, extra: [RowAction] = []) -> some View {
        modifier(RowActionsModifier(edit: edit, delete: delete, extra: extra))
    }
}
