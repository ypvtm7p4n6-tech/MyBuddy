import SwiftUI

// MARK: - Alle spaarpotten

struct PotsPage: View {
    @Environment(AppStore.self) private var store
    @State private var showNew = false
    @State private var showPicker = false

    var body: some View {
        let d = store.data
        let now = store.now
        PageScaffold(title: "Spaarpotten") {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Totaal gespaard", symbol: "tray.full.fill", tint: Theme.olive.opacity(0.3)) {
                    BigAmount(value: d.totalSaved(current: now))
                    HStack(spacing: 8) {
                        StatTile(title: "Deze maand erbij", value: Fmt.euro(d.savedTotal(in: now)))
                        StatTile(title: "Aantal potten", value: "\(d.pots.count)")
                    }
                }

                if d.pots.isEmpty {
                    GlassBlock(title: "Nog geen spaarpotten") {
                        EmptyHint(symbol: "tray", title: "Maak je eerste spaarpot",
                                  message: "Geef elke pot een doel, bijvoorbeeld een buffer, een vakantie of een nieuwe laptop.",
                                  actionTitle: "Nieuwe spaarpot") { showNew = true }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Theme.pageSpacing, alignment: .top)],
                              spacing: Theme.pageSpacing) {
                        ForEach(d.pots) { pot in PotRowCard(pot: pot) }
                    }
                    ChipGrid {
                        ChipButton(title: "Nieuwe spaarpot", symbol: "plus") { showNew = true }
                        ChipButton(title: "Kies potten voor Home", symbol: "slider.horizontal.3") { showPicker = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) { PotEditSheet(pot: nil) }
        .sheet(isPresented: $showPicker) { PotPickerSheet() }
    }
}

struct PotRowCard: View {
    @Environment(AppStore.self) private var store
    let pot: Pot

    var body: some View {
        let d = store.data
        let now = store.now
        let balance = d.potBalance(pot.id, at: now)
        let progress = d.potProgress(pot.id, current: now)
        let color = Theme.color(pot.colorIndex)
        NavigationLink(value: Destination.pot(pot.id)) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: pot.symbol, color: color, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pot.name).font(.headline).lineLimit(1)
                        Spacer()
                        Text(Fmt.euro(balance)).font(.system(.headline, design: .rounded, weight: .bold))
                    }
                    if let goal = pot.goalAmount, let progress {
                        ProgressBar(progress: progress, tint: color)
                        HStack {
                            Text("Doel \(Fmt.euroWhole(goal))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.percent(progress, digits: 0)).font(.caption.weight(.semibold)).foregroundStyle(color)
                        }
                    } else {
                        Text("Geen doel ingesteld").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Eén spaarpot

enum PotAction: String, Identifiable {
    case deposit, withdraw, setBalance, transfer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit: return "Geld storten"
        case .withdraw: return "Geld opnemen"
        case .setBalance: return "Saldo aanpassen"
        case .transfer: return "Overboeken"
        }
    }

    var symbol: String {
        switch self {
        case .deposit: return "plus.circle.fill"
        case .withdraw: return "minus.circle.fill"
        case .setBalance: return "slider.horizontal.3"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
}

struct PotDetailPage: View {
    let potID: UUID
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var action: PotAction?
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        if let pot = store.data.pot(potID) {
            content(pot)
        } else {
            PageScaffold(title: "Spaarpot") {
                EmptyHint(symbol: "questionmark.folder", title: "Deze spaarpot bestaat niet meer")
            }
        }
    }

    @ViewBuilder
    private func content(_ pot: Pot) -> some View {
        let d = store.data
        let now = store.now
        let balance = d.potBalance(pot.id, at: now)
        let progress = d.potProgress(pot.id, current: now)
        let color = Theme.color(pot.colorIndex)
        let timeline = d.potTimeline(pot.id, current: now)
        let thisMonth = d.allocation(pot.id, in: now)

        PageScaffold(title: pot.name) {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: "Saldo", symbol: pot.symbol, tint: color.opacity(0.28)) {
                    HStack(spacing: 18) {
                        ZStack {
                            ProgressRing(progress: progress ?? 1, tint: color, lineWidth: 10)
                                .frame(width: 96, height: 96)
                            if let progress {
                                Text(Fmt.percent(progress, digits: 0)).font(.headline)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            BigAmount(value: balance, font: .system(.title, design: .rounded, weight: .bold))
                            if let goal = pot.goalAmount {
                                Text("van \(Fmt.euro(goal))").font(.subheadline).foregroundStyle(.secondary)
                                Text(balance >= goal ? "Doel bereikt" : "Nog \(Fmt.euro(goal - balance)) te gaan")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(balance >= goal ? Theme.positive : color)
                            } else {
                                Text("Geen doel ingesteld").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    goalText(pot, balance: balance)
                }

                GlassBlock(title: "Geld bewegen", symbol: "arrow.up.arrow.down") {
                    ChipGrid {
                        actionButton(.deposit)
                        actionButton(.withdraw)
                        actionButton(.setBalance)
                        if d.pots.count > 1 { actionButton(.transfer) }
                    }
                }

                GlassBlock(title: "Inleg", symbol: "calendar") {
                    HStack(spacing: 8) {
                        StatTile(title: "Deze maand erbij", value: Fmt.euro(thisMonth))
                        StatTile(title: "Standaard per maand", value: Fmt.euro(pot.monthlyContribution))
                    }
                    ChipGrid {
                        ChipButton(title: "Doel en instellingen", symbol: "pencil") { showEdit = true }
                        ChipLink(title: "Verdelen", symbol: "square.split.2x2", destination: .distribute)
                    }
                }

                GlassBlock(title: "Waar is het geld heen gegaan?", symbol: "clock.arrow.circlepath") {
                    if timeline.isEmpty {
                        Text("Nog geen boekingen.").font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(timeline) { item in
                            timelineRow(item)
                            if item.id != timeline.last?.id { Divider() }
                        }
                    }
                }

                ChipButton(title: "Spaarpot verwijderen", symbol: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(item: $action) { act in PotEntrySheet(pot: pot, action: act) }
        .sheet(isPresented: $showEdit) { PotEditSheet(pot: pot) }
        .confirmationDialog("Deze spaarpot verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder \(pot.name)", role: .destructive) {
                let id = pot.id
                store.mutate { $0.deletePot(id) }
                dismiss()
            }
        } message: {
            Text("De boekingen van deze pot verdwijnen ook.")
        }
    }

    private func actionButton(_ a: PotAction) -> some View {
        ChipButton(title: a.title, symbol: a.symbol) { action = a }
    }

    @ViewBuilder
    private func goalText(_ pot: Pot, balance: Double) -> some View {
        let d = store.data
        if let goal = pot.goalAmount, goal > 0 {
            if balance >= goal {
                EmptyView()
            } else if let month = d.potGoalMonth(pot.id, current: store.now) {
                Label("Bij je geplande inleg is het doel bereikt in \(Fmt.month(month)).", systemImage: "flag.checkered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Stel een maandelijkse inleg in om te zien wanneer je er bent.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let date = pot.goalDate {
                let months = store.now.months(to: YearMonth(date: date))
                if months > 0 && balance < goal {
                    let needed = ((goal - balance) / Double(months)).cents
                    Label("Voor \(Fmt.month(YearMonth(date: date))) heb je \(Fmt.euro(needed)) per maand nodig.", systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timelineRow(_ item: PotTimelineItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.note.isEmpty ? Fmt.date(item.date) : "\(Fmt.date(item.date)) · \(item.note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((item.amount >= 0 ? "+" : "") + Fmt.euro(item.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.amount >= 0 ? Theme.positive : Theme.negative)
            if !item.isMonthlyAllocation, let entryID = UUID(uuidString: item.id) {
                Menu {
                    Button("Verwijder boeking", role: .destructive) {
                        store.mutate { $0.deletePotEntry(entryID) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Sheets

struct PotEntrySheet: View {
    let pot: Pot
    let action: PotAction

    @Environment(AppStore.self) private var store
    @State private var amount = 0.0
    @State private var note = ""
    @State private var targetID: UUID?
    @State private var viaBank = false

    private var others: [Pot] { store.data.pots.filter { $0.id != pot.id } }

    var body: some View {
        let balance = store.data.potBalance(pot.id, at: store.now)
        SheetScaffold(title: action.title, canSave: canSave(balance: balance), onSave: { save() }) {
            Section {
                switch action {
                case .deposit, .withdraw:
                    NumberRow(title: "Bedrag", value: $amount)
                case .setBalance:
                    NumberRow(title: "Nieuw saldo", value: $amount)
                case .transfer:
                    NumberRow(title: "Bedrag", value: $amount)
                    Picker("Naar", selection: $targetID) {
                        ForEach(others) { other in Text(other.name).tag(other.id as UUID?) }
                    }
                }
                if action != .transfer {
                    TextField("Waarvoor? (optioneel)", text: $note)
                }
                if action == .deposit || action == .withdraw {
                    Toggle(action == .deposit ? "Van de bankrekening" : "Naar de bankrekening", isOn: $viaBank)
                }
            } header: {
                Text("Huidig saldo \(Fmt.euro(balance))")
            } footer: {
                if action == .setBalance {
                    Text("Het verschil wordt als correctie in de geschiedenis gezet.")
                }
            }
        }
        .onAppear {
            if action == .setBalance { amount = balance }
            if targetID == nil { targetID = others.first?.id }
        }
    }

    private func canSave(balance: Double) -> Bool {
        switch action {
        case .deposit: return amount > 0
        case .withdraw: return amount > 0 && amount <= balance + 0.005
        case .setBalance: return amount >= 0
        case .transfer: return amount > 0 && amount <= balance + 0.005 && targetID != nil
        }
    }

    private func save() {
        let id = pot.id
        let a = amount
        let n = note.trimmingCharacters(in: .whitespaces)
        let now = store.now
        let target = targetID
        switch action {
        case .deposit:
            if viaBank {
                store.mutate { $0.transferBankToPot(potID: id, amount: a, note: n) }
            } else {
                store.mutate { $0.addPotEntry(potID: id, amount: a, kind: .deposit, note: n) }
            }
        case .withdraw:
            if viaBank {
                store.mutate { $0.transferPotToBank(potID: id, amount: a, note: n) }
            } else {
                store.mutate { $0.addPotEntry(potID: id, amount: -a, kind: .withdrawal, note: n) }
            }
        case .setBalance:
            store.mutate { $0.setPotBalance(id, to: a, current: now, note: n) }
        case .transfer:
            if let target { store.mutate { $0.transfer(from: id, to: target, amount: a) } }
        }
    }
}

struct PotEditSheet: View {
    let pot: Pot?

    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var symbol = "banknote"
    @State private var colorIndex = 0
    @State private var goal: Double?
    @State private var goalDate: Date?
    @State private var monthly = 0.0
    @State private var opening = 0.0

    var body: some View {
        SheetScaffold(title: pot == nil ? "Nieuwe spaarpot" : "Spaarpot aanpassen",
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                      onSave: { save() }) {
            Section("Naam") {
                TextField("Bijvoorbeeld Vakantie", text: $name)
            }
            Section("Uiterlijk") {
                SymbolChoiceRow(symbol: $symbol, color: Theme.color(colorIndex))
                ColorChoiceRow(index: $colorIndex)
            }
            Section {
                OptionalNumberRow(title: "Doelbedrag", value: $goal, defaultValue: 1000)
                OptionalDateRow(title: "Streefdatum", date: $goalDate)
            } header: {
                Text("Doel")
            } footer: {
                Text("Met een doelbedrag laat de app zien hoe ver je bent en wanneer je er bent.")
            }
            Section {
                NumberRow(title: "Standaard inleg per maand", value: $monthly)
                if pot == nil {
                    NumberRow(title: "Beginsaldo", value: $opening)
                }
            } header: {
                Text("Geld")
            } footer: {
                Text("De standaard inleg komt elke maand in je verdeling; die kun je per maand aanpassen.")
            }
        }
        .onAppear {
            if let pot {
                name = pot.name
                symbol = pot.symbol
                colorIndex = pot.colorIndex
                goal = pot.goalAmount
                goalDate = pot.goalDate
                monthly = pot.monthlyContribution
            } else {
                colorIndex = store.data.pots.count % Theme.palette.count
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let now = store.now
        if var existing = pot {
            existing.name = trimmed
            existing.symbol = symbol
            existing.colorIndex = colorIndex
            existing.goalAmount = goal
            existing.goalDate = goalDate
            existing.monthlyContribution = monthly.cents
            let updated = existing
            store.mutate { $0.updatePot(updated, current: now) }
        } else {
            let created = Pot(name: trimmed, symbol: symbol, colorIndex: colorIndex,
                              goalAmount: goal, goalDate: goalDate,
                              monthlyContribution: monthly.cents, startMonth: now)
            let start = opening
            store.mutate { $0.addPot(created, openingBalance: start) }
        }
    }
}
