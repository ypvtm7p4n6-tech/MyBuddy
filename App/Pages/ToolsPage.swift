import SwiftUI

// Hulpmiddelen (`.tools`, par. 3 van docs/design2/plan.md): de vier rekenhulpen Noodbuffer, Versnellers, Toekomstschatting en
// Aankoopcheck als lijst. Elke rij heeft de tegel van zijn pagina (symbool en kleur uit `PageCatalog`) en een regel uitleg: de
// tekst die op de oude kaart van het hulpmiddel stond. Alleen inhoud: de stapel komt van `TabStack`.

/// De pagina Hulpmiddelen.
struct ToolsPage: View {
    private let tools: [ToolHint] = ToolHint.all

    var body: some View {
        ListScaffold(title: "Hulpmiddelen") {
            Section {
                ForEach(tools) { tool in
                    ToolsRow(tool: tool)
                }
            }
        }
    }
}

/// Een hulpmiddel met de regel uitleg die erbij hoort.
struct ToolHint: Identifiable {
    let destination: Destination
    let hint: String

    var id: String { String(describing: destination) }

    /// De vier hulpmiddelen in vaste volgorde, met de uitleg van de oude kaarten op het tabblad Plannen.
    static let all: [ToolHint] = [
        ToolHint(destination: .buffer,
                 hint: "Vul je uitgaven in, dan rekent de app uit hoeveel noodbuffer bij je past."),
        ToolHint(destination: .accelerators,
                 hint: "Maak eerst een doel. Daarna zoekt de app in jouw gegevens wat het sneller maakt."),
        ToolHint(destination: .projection,
                 hint: "Vul beleggingen in en reken uit wat ze over dagen, maanden of jaren waard zijn."),
        ToolHint(destination: .purchase,
                 hint: "Zet een aankoop tegenover je werktijd en kijk of je er genoeg uren voor over hebt.")
    ]
}

/// Eén rij van Hulpmiddelen, met titel, symbool en tint uit `PageCatalog` en de uitleg als ondertitel.
struct ToolsRow: View {
    let tool: ToolHint
    @Environment(AppStore.self) private var store

    /// De uitleg; Versnellers noemt het eerste doel zodra er een is (zoals de oude kaart "Voor <doel>").
    private var hint: String {
        if tool.destination == .accelerators, let goal = store.data.goals.first {
            return "De app zoekt in jouw gegevens wat \(goal.name) sneller maakt."
        }
        return tool.hint
    }

    var body: some View {
        if let info = PageCatalog.info(tool.destination) {
            MediaRow(symbol: info.symbol, hue: info.hue, title: info.title, subtitle: hint,
                     destination: tool.destination)
        }
    }
}
