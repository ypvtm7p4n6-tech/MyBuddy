import SwiftUI

// MARK: - Bankrekening (ook je uitgaven)

enum BankAction: String, Identifiable {
    case balance, deposit, withdraw, toPot, fromPot
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: return "Saldo invullen"
        case .deposit: return "Geld storten"
        case .withdraw: return "Geld opnemen"
        case .toPot: return "Naar spaarpot"
        case .fromPot: return "Van spaarpot"
        }
    }

    var symbol: String {
        switch self {
        case .balance: return "square.and.pencil"
        case .deposit: return "plus.circle"
        case .withdraw: return "minus.circle"
        case .toPot: return "arrow.right.circle"
        case .fromPot: return "arrow.left.circle"
        }
    }
}

/// De bankrekening in de app: hier komt je salaris binnen, hier gaan je uitgaven vanaf
/// en vanaf hier zet je geld over naar spaarpotten en beleggingen. Het is geen echte bank.
struct BankPage: View {
    @Environment(Router.self) private var router
    @State private var action: BankAction?

    var body: some View {
        let month = router.focusMonth
        PageScaffold(title: "Bankrekening") {
            // Twee groepen: een ViewBuilder kent maximaal 10 kinderen per container.
            VStack(spacing: Theme.pageSpacing) {
                Group {
                    BankBalanceBlock(action: $action)
                    BankLowPointNotice(month: month)
                    MonthPickerBlock()
                    BankDayBlock()
                    BankUpcomingBlock()
                    BankFlowBlock(month: month)
                }
                Group {
                    MoneyLinesBlock(kind: .expense, expenseKind: .fixed, month: month)
                    MoneyLinesBlock(kind: .expense, expenseKind: .variable, month: month)
                    BankTransfersBlock(month: month)
                    BankForecastBlock()
                    BankBufferBlock()
                    BankHistoryBlock()
                }
            }
        }
        .sheet(item: $action) { act in BankActionSheet(action: act) }
    }
}

/// Het saldo van de bankrekening van nu. Dit is hetzelfde getal als het saldo aan het eind van vandaag op de dagpagina
/// (`DayTotals.bankBalance`): alles gebeurt per kalenderdag, dus wat vandaag op je plan staat telt al mee. Het eindsaldo
/// van de maand is `bankBalance(at:)` (`MonthLedger.closingBank`).
struct BankBalanceBlock: View {
    @Environment(AppStore.self) private var store
    @Binding var action: BankAction?

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // Alleen een saldo tonen als het van nu bekend is: een saldo dat pas later begint zegt niets over vandaag.
        let balanceNow = d.bankBalanceNowIfKnown(current: now, today: today)
        let monthEnd = d.bankBalance(at: now)
        GlassBlock(title: "Saldo nu", symbol: "building.columns.fill",
                   subtitle: balanceNow == nil ? nil : "Vandaag, \(DayText.weekdayShort(today))",
                   tint: Theme.olive.opacity(0.3)) {
            if let balanceNow {
                BigAmount(value: balanceNow, color: balanceNow < 0 ? Theme.negative : Color.primary)
                if let monthEnd {
                    StatTile(title: "Eind van \(Fmt.month(now))", value: Fmt.euro(monthEnd),
                             color: monthEnd < 0 ? Theme.negative : Color.primary,
                             caption: "verwacht, met alles wat nog komt")
                }
                Text(explanation(d))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if d.hasBankBalance {
                EmptyHint(symbol: "calendar.badge.clock", title: "Je saldo van vandaag is nog niet bekend",
                          message: "Wat je invulde begint pas op een latere dag. Vul je saldo van vandaag in.")
            } else {
                EmptyHint(symbol: "building.columns", title: "Begin met je saldo",
                          message: "Je koppelt geen bank. Vul je saldo in of zet er geld op; de app houdt het bij en rekent ermee verder.")
            }
            ChipGrid {
                ChipButton(title: "Geld storten", symbol: BankAction.deposit.symbol) { action = .deposit }
                ChipButton(title: "Geld opnemen", symbol: BankAction.withdraw.symbol) { action = .withdraw }
                if !d.pots.isEmpty {
                    ChipButton(title: "Naar spaarpot", symbol: BankAction.toPot.symbol) { action = .toPot }
                    ChipButton(title: "Van spaarpot", symbol: BankAction.fromPot.symbol) { action = .fromPot }
                }
                ChipButton(title: "Saldo invullen", symbol: BankAction.balance.symbol) { action = .balance }
            }
        }
    }

    /// Hoe het saldo tot stand komt, met de regel voor een ingevuld saldo.
    private func explanation(_ d: FinanceData) -> String {
        let perDay = "Het saldo telt per dag: wat vandaag op je plan staat, is al meegerekend."
        if let last = d.sortedBankSnapshots.last {
            return "Laatst ingevuld: \(Fmt.euro(last.balance)) op \(Fmt.date(last.date)). Boekingen van de dag waarop je het saldo invult gelden als al verwerkt. Stortingen, opnames en alles wat je plant komen daar bovenop, op de dag waarop het gebeurt. \(perDay)"
        }
        return "Het saldo volgt je stortingen, opnames en alles wat je plant, op de dag waarop het gebeurt. \(perDay)"
    }
}

/// Wat er in een maand binnenkomt, uitgaat en overblijft, met een knop om de standaardposten in te vullen.
/// Onderaan staat het saldo aan het eind van de maand (`bankBalance(at:)`, hetzelfde als `MonthLedger.closingBank`).
struct BankFlowBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store
    @State private var message: String?

    /// Het deel van de uitgaven van één soort dat van de bankrekening gaat, zoals de rekenmotor het boekt per regel.
    private func bankPart(_ d: FinanceData, kind: ExpenseKind) -> Double {
        guard month >= d.startMonth else { return 0 }
        return CentsMath.value(CentsMath.sum(d.expenseLines(in: month, kind: kind).map { CentsMath.int(d.fromBank(of: $0)) }))
    }

    var body: some View {
        let d = store.data
        let o = d.expenseOverview(in: month)
        let missing = d.missingStandardExpenses(in: month).count
        // De balk toont wat van de bank gaat, zodat alle stukken samen het inkomen vormen.
        let fixedBank = bankPart(d, kind: .fixed)
        let variableBank = bankPart(d, kind: .variable)
        GlassBlock(title: "Binnen en eruit", symbol: "arrow.left.arrow.right",
                   subtitle: month > store.now ? "\(Fmt.month(month)) · verwacht" : Fmt.month(month)) {
            SegmentBar(segments: [
                SegmentBar.Segment(id: "fixed", value: fixedBank, color: Theme.flowExpenses),
                SegmentBar.Segment(id: "variable", value: variableBank, color: Theme.flowVariable),
                SegmentBar.Segment(id: "pots", value: o.toPots, color: Theme.flowSaved),
                SegmentBar.Segment(id: "invest", value: o.toInvestments, color: Theme.flowInvested),
                SegmentBar.Segment(id: "free", value: max(0, o.leftAfterTransfers), color: Theme.flowFree)
            ])
            VStack(spacing: 0) {
                FlowRow(title: "Salaris en inkomsten", value: o.income, sign: "+", color: Theme.positive)
                FlowRow(title: "Vaste uitgaven", value: o.fixed, sign: "−", dot: Theme.flowExpenses)
                FlowRow(title: "Variabele uitgaven", value: o.variable, sign: "−", dot: Theme.flowVariable)
                if o.fromPots > 0 {
                    FlowRow(title: "Betaald uit spaarpotten", value: o.fromPots, sign: "+", dot: Theme.flowSaved)
                }
                Divider().padding(.vertical, 4)
                FlowRow(title: "Over na uitgaven", value: o.leftAfterExpenses, bold: true,
                        color: o.leftAfterExpenses < 0 ? Theme.negative : Color.primary)
                FlowRow(title: "Naar spaarpotten", value: o.toPots, sign: "−", dot: Theme.flowSaved)
                FlowRow(title: "Naar beleggingen", value: o.toInvestments, sign: "−", dot: Theme.flowInvested)
                Divider().padding(.vertical, 4)
                FlowRow(title: "Over op de rekening", value: o.leftAfterTransfers, bold: true,
                        color: o.leftAfterTransfers < 0 ? Theme.negative : Theme.positive)
            }
            if let note = payoutNote(d) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if o.leftAfterTransfers < 0 {
                Text("Je geeft meer uit en verdeelt meer dan je inkomen. Pas je uitgaven of je verdeling aan.")
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
            endBalance(d)
            ChipGrid {
                ChipButton(title: missing == 0 ? "Standaardposten staan erin" : "Standaard uitgaven invullen",
                           symbol: "wand.and.stars") {
                    let added = store.data.missingStandardExpenses(in: month).count
                    withAnimation(Theme.motion) { store.mutate { $0.fillStandardExpenses(in: month) } }
                    message = added == 0 ? "Alle standaardposten staan al in deze maand."
                                         : "\(added) standaardposten ingevuld met een richtbedrag. Ze komen elke maand terug; pas ze aan naar jouw situatie."
                }
                ChipLink(title: "Geld verdelen", symbol: "square.split.2x2", destination: .distribute)
                ChipLink(title: "Dag voor dag", symbol: "calendar", destination: .cashflow)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if missing > 0 {
                Text("De knop vult gangbare vaste en variabele posten in met een richtbedrag, als terugkerende regel. Je kunt alles daarna aanpassen of verwijderen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Komt het salaris vaker dan één keer in de maand binnen, dan staat hier wanneer.
    private func payoutNote(_ d: FinanceData) -> String? {
        let payouts = d.salaryPayouts(in: month, plan: d.plan(for: month)).filter { $0.cents != 0 }
        guard payouts.count > 1 else { return nil }
        return "Je salaris komt in \(Fmt.month(month)) \(payouts.count) keer binnen: \(d.salaryPayoutDaysText(in: month))."
    }

    /// Het saldo van de rekening aan het eind van de maand: begin, binnen, eruit en overgeschreven, met handmatige boekingen
    /// en je ingevulde saldo erbij. Per dag staat het bij Dag voor dag.
    @ViewBuilder
    private func endBalance(_ d: FinanceData) -> some View {
        if let closing = d.bankBalance(at: month) {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                FlowRow(title: "Saldo aan het eind van de maand", value: closing, bold: true,
                        color: closing < 0 ? Theme.negative : Color.primary)
                Text("Dit is het saldo van je rekening, met je eigen stortingen, opnames en ingevulde saldo. Per dag zie je het bij Dag voor dag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FlowRow: View {
    let title: String
    let value: Double
    var sign: String = ""
    var bold = false
    var color: Color = .primary
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(title)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(sign + Fmt.euro(value))
                .font(bold ? .subheadline.weight(.bold) : .subheadline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: value)
        }
        .padding(.vertical, 5)
    }
}

/// Overschrijvingen vanaf de rekening naar spaarpotten en beleggingen, volgens je maandverdeling, met de dag.
/// Bij een percentage staat erbij welk percentage het is; het bedrag is altijd wat de rekenmotor van dat percentage maakt.
struct BankTransfersBlock: View {
    let month: YearMonth
    @Environment(AppStore.self) private var store

    private struct Row: Identifiable {
        let id: UUID
        let symbol: String
        let color: Color
        let title: String
        let amount: Double
        let day: Int
        let detail: String
    }

    /// "de 25e" of, bij een percentage, "de 25e · 10% van je salaris".
    private func detail(_ d: FinanceData, id: UUID, day: Int) -> String {
        let rule = d.allocationRule(id, in: month)
        return rule.isPercent ? "\(DayText.ordinal(day)) · \(rule.summary)" : DayText.ordinal(day)
    }

    var body: some View {
        let d = store.data
        let potRows: [Row] = d.pots.map { pot in
            let day = d.transferDay(for: pot.id, in: month)
            return Row(id: pot.id, symbol: pot.symbol, color: Theme.color(pot.colorIndex), title: pot.name,
                       amount: d.allocation(pot.id, in: month), day: day, detail: detail(d, id: pot.id, day: day))
        }.filter { $0.amount != 0 }
        let holdingRows: [Row] = d.holdings.map { h in
            let day = d.transferDay(for: h.id, in: month)
            return Row(id: h.id, symbol: h.kind.symbol, color: Theme.flowInvested, title: h.name,
                       amount: d.allocation(h.id, in: month), day: day, detail: detail(d, id: h.id, day: day))
        }.filter { $0.amount != 0 }
        let rows = (potRows + holdingRows).sorted { lhs, rhs in
            lhs.day != rhs.day ? lhs.day < rhs.day : lhs.title < rhs.title
        }
        // Samen precies wat het overzicht als gespaard en belegd telt.
        let figures = d.monthFigures(month)
        let total = CentsMath.value(CentsMath.add(figures.saved, figures.invested))
        GlassBlock(title: "Overschrijvingen", symbol: "arrow.up.right.circle.fill",
                   subtitle: "Van de rekening naar spaarpotten en beleggingen", headerLink: .distribute) {
            if rows.isEmpty {
                Text("Je hebt voor \(Fmt.month(month)) nog niets verdeeld. Tik hier om geld te verdelen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        TransferRow(symbol: row.symbol, color: row.color, title: row.title, amount: row.amount,
                                    dayText: row.detail)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(10)
                .tile()
                HStack {
                    Text("Totaal overgeschreven").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Fmt.euro(total))
                        .font(.subheadline.weight(.bold))
                        .contentTransition(.numericText())
                        .animation(Theme.motion, value: total)
                }
                Text("Op de overschrijfdag gaat het bedrag automatisch naar de pot of belegging, ook in maanden die nog komen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TransferRow: View {
    let symbol: String
    let color: Color
    let title: String
    let amount: Double
    var dayText: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
                if let dayText {
                    Text(dayText).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            // Een negatieve verdeling betekent geld terug naar de rekening.
            Text((amount < 0 ? "+" : "−") + Fmt.euro(abs(amount)))
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Theme.motion, value: amount)
        }
    }
}

struct BankForecastBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let now = store.now
        let series = store.data.bankSeries(from: now.adding(-3), count: 16, current: now).map { TimePoint($0) }
        if series.count > 1 {
            GlassBlock(title: "Verwacht verloop", symbol: "chart.line.uptrend.xyaxis",
                       subtitle: "Saldo aan het eind van elke maand") {
                TimeLineChart(points: series, height: 160)
                Text("Gebaseerd op je saldo, inkomen, uitgaven en verdeling per maand. Het eindsaldo van een maand is hetzelfde getal als bij Binnen en eruit en bij Dag voor dag. De grafiek past zich aan als je iets wijzigt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BankBufferBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let d = store.data
        let now = store.now
        // Alleen als het saldo van nu bekend is: zonder saldo zegt "daarboven" niets.
        if d.hasBankBalanceNow(current: now, today: store.today) {
            GlassBlock(title: "Bankbuffer", symbol: "shield.lefthalf.filled",
                       subtitle: "Het minimum dat je op je rekening wilt houden") {
                HStack(spacing: 8) {
                    StatTile(title: "Gewenste bankbuffer", value: Fmt.euro(d.bankBuffer(current: now)))
                    StatTile(title: "Daarboven", value: Fmt.euro(d.bankSurplusAboveBuffer(current: now, today: store.today)),
                             color: Theme.positive)
                }
                NumberRow(title: "Bankbuffer in maanden aan uitgaven",
                          value: Binding(get: { store.data.settings.bankBufferMonths },
                                         set: { v in store.mutate { $0.settings.bankBufferMonths = v } }),
                          unit: .plain("mnd"), maxDigits: 1)
                Text("Dit is iets anders dan je noodbuffer: de bankbuffer is wat er minstens op je betaalrekening hoort te staan. Hoeveel noodbuffer je nodig hebt (op je spaarrekening of in een spaarpot) reken je uit met de buffercalculator.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ChipLink(title: "Buffercalculator", symbol: "shield.lefthalf.filled", destination: .buffer)
            }
        }
    }
}

struct BankHistoryBlock: View {
    @Environment(AppStore.self) private var store
    /// Een boeking waarvan het verwijderen eerst om een bevestiging vraagt, omdat er een andere helft bij hoort.
    @State private var pendingDelete: PendingDelete?

    private struct PendingDelete: Identifiable {
        let id: UUID
        let message: String
    }

    private struct Item: Identifiable {
        let id: UUID
        let date: Date
        let title: String
        let detail: String
        let amount: Double
        let isSnapshot: Bool
    }

    var body: some View {
        let d = store.data
        let items: [Item] = (d.bankSnapshots.map { s in
            Item(id: s.id, date: s.date, title: "Saldo ingevuld", detail: s.note, amount: s.balance, isSnapshot: true)
        } + d.bankEntries.map { e in
            Item(id: e.id, date: e.date, title: e.kind.title, detail: e.note, amount: e.amount, isSnapshot: false)
        }).sorted { $0.date > $1.date }

        if !items.isEmpty {
            GlassBlock(title: "Geschiedenis", symbol: "clock.arrow.circlepath") {
                VStack(spacing: 0) {
                    ForEach(items.prefix(40)) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail.isEmpty ? Fmt.date(item.date) : "\(Fmt.date(item.date)) · \(item.detail)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            Text(item.isSnapshot ? Fmt.euro(item.amount) : (item.amount >= 0 ? "+" : "") + Fmt.euro(item.amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.isSnapshot || item.amount >= 0 ? Color.primary : Theme.negative)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Menu {
                                Button("Verwijder", role: .destructive) { requestDelete(item) }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.vertical, 8)
                        if item.id != items.prefix(40).last?.id { Divider() }
                    }
                }
            }
            .confirmationDialog("Boeking verwijderen?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { pending in
                Button("Verwijder", role: .destructive) { delete(pending.id, snapshot: false) }
            } message: { pending in
                Text(pending.message)
            }
        }
    }

    /// Een ingevuld saldo en een losse storting of opname verdwijnen meteen. Hoort een boeking bij een overboeking
    /// naar of van een spaarpot, dan vraagt de app eerst om bevestiging en zegt ze wat er verdwijnt.
    private func requestDelete(_ item: Item) {
        if !item.isSnapshot, let message = confirmationMessage(forBankEntry: item.id) {
            pendingDelete = PendingDelete(id: item.id, message: message)
        } else {
            delete(item.id, snapshot: item.isSnapshot)
        }
    }

    private func delete(_ id: UUID, snapshot: Bool) {
        withAnimation(Theme.motion) {
            store.mutate { data in
                if snapshot { data.deleteBankSnapshot(id) } else { data.deleteBankEntry(id) }
            }
        }
    }

    /// De tekst voor de bevestiging, of nil als de boeking los staat (dan is verwijderen veilig).
    private func confirmationMessage(forBankEntry id: UUID) -> String? {
        let d = store.data
        guard let entry = d.bankEntries.first(where: { $0.id == id }) else { return nil }
        // Een overboeking met `pairID`: de rekenmotor verwijdert beide helften en zegt zelf wat er verdwijnt.
        if let warning = d.pairedEntries(ofBank: id).warning { return warning }
        // Een oude overboeking zonder `pairID`: alleen de kant op de bankrekening verdwijnt.
        if entry.kind == .toPot || entry.kind == .fromPot {
            return "Dit verwijdert alleen de boeking op de bankrekening. De bijbehorende boeking bij de spaarpot blijft staan; die verwijder je bij de spaarpot."
        }
        return nil
    }
}

struct BankActionSheet: View {
    let action: BankAction

    @Environment(AppStore.self) private var store
    @State private var amount = 0.0
    @State private var note = ""
    @State private var potID: UUID?

    var body: some View {
        let d = store.data
        let now = store.now
        let today = store.today
        // Saldo's van nu, per kalenderdag: wat vandaag op je plan staat telt al mee, wat op een latere dag komt (het salaris
        // van de 25e, de inleg) nog niet.
        let bank = d.bankBalanceNowIfKnown(current: now, today: today)
        let potBalance = potID.map { d.potBalanceNow($0, current: now, today: today) } ?? 0
        SheetScaffold(title: action.title, canSave: canSave(potBalance: potBalance), onSave: { save() }) {
            Section {
                if action == .toPot || action == .fromPot {
                    if d.pots.isEmpty {
                        Text("Je hebt nog geen spaarpotten.").foregroundStyle(.secondary)
                    } else {
                        Picker("Spaarpot", selection: $potID) {
                            ForEach(d.pots) { pot in Text(pot.name).tag(pot.id as UUID?) }
                        }
                    }
                }
                NumberRow(title: action == .balance ? "Saldo nu" : "Bedrag", value: $amount, allowsNegative: action == .balance)
                TextField("Notitie (optioneel)", text: $note)
            } header: {
                Text(headerText(bank: bank, potBalance: potBalance))
            } footer: {
                Text(footerText)
            }
        }
        .onAppear {
            if action == .balance { amount = bank ?? 0 }
            if potID == nil { potID = d.pots.first?.id }
        }
    }

    private func headerText(bank: Double?, potBalance: Double) -> String {
        let bankText = bank.map { Fmt.euro($0) } ?? "onbekend"
        switch action {
        case .fromPot: return "Saldo spaarpot \(Fmt.euro(potBalance)) · bankrekening \(bankText)"
        default: return "Saldo bankrekening \(bankText)"
        }
    }

    private var footerText: String {
        switch action {
        case .balance: return "Vul het saldo in zoals het nu op je rekening staat. Boekingen van de dag waarop je het saldo invult gelden als al verwerkt. Elke invoer wordt bewaard."
        case .deposit: return "Dit zet geld op de bankrekening in de app. Er gebeurt niets bij een echte bank."
        case .withdraw: return "Dit haalt geld van de bankrekening in de app, bijvoorbeeld voor contant geld of een grote uitgave."
        case .toPot: return "Het bedrag gaat van de bankrekening naar de spaarpot en staat in de geschiedenis van beide."
        case .fromPot: return "Het bedrag gaat van de spaarpot terug naar de bankrekening."
        }
    }

    private func canSave(potBalance: Double) -> Bool {
        switch action {
        case .balance: return true
        case .deposit, .withdraw: return amount > 0
        case .toPot: return amount > 0 && potID != nil
        case .fromPot: return amount > 0 && potID != nil && amount <= potBalance + 0.005
        }
    }

    private func save() {
        let a = amount
        let n = note.trimmingCharacters(in: .whitespaces)
        let pot = potID
        withAnimation(Theme.motion) { apply(amount: a, note: n, potID: pot) }
    }

    private func apply(amount a: Double, note n: String, potID pot: UUID?) {
        switch action {
        case .balance:
            store.mutate { $0.addBankSnapshot(balance: a, note: n) }
        case .deposit:
            store.mutate { $0.addBankEntry(amount: a, note: n) }
        case .withdraw:
            store.mutate { $0.addBankEntry(amount: -a, note: n) }
        case .toPot:
            if let pot { store.mutate { $0.transferBankToPot(potID: pot, amount: a, note: n) } }
        case .fromPot:
            if let pot { store.mutate { $0.transferPotToBank(potID: pot, amount: a, note: n) } }
        }
    }
}
