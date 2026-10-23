import SwiftUI

// De logica van de dagschermen (zonder SwiftUI: dagen in woorden, het dagboek per scherm, de sluitende regels, de controle en de
// waarschuwing) staat in App/UI/CashflowDisplay.swift, zodat de tests in CoreTests haar meecompileren en meedraaien.
// De pagina Bankrekening met Dag voor dag staat in App/Pages/Bank/. Hier staan de bouwstenen daarvan: een gebeurtenis, de cijfers
// van een dag, een regel van een sluitend overzicht, de melding bij een afwijking en de waarschuwing bij een laag saldo.

// MARK: - Een gebeurtenis in beeld

/// Hoe een gebeurtenis eruitziet: icoon, kleur en bedrag. Inkomen en rente positief, uitgaven negatief, inleg in potten en
/// beleggingen in de accentkleur. De kleur staat nooit alleen: er staat altijd een teken en een soort bij.
struct DayEventStyle {
    let symbol: String
    let color: Color
    let kindText: String
    let amount: Double
    let isInterest: Bool

    init(_ event: DayEvent) {
        let shown = event.bankAmount != 0 ? event.bankAmount : event.potAmount
        amount = shown
        isInterest = event.kind == .interest
        switch event.kind {
        case .salary:
            symbol = "briefcase.fill"
            color = Theme.positive
            kindText = "Salaris"
        case .income:
            symbol = "plus.circle.fill"
            color = Theme.positive
            kindText = "Overige inkomsten"
        case .expense:
            let fromPotOnly = event.bankAmount == 0 && event.potAmount != 0
            symbol = fromPotOnly ? "tray.full.fill" : "minus.circle.fill"
            color = Theme.negative
            kindText = fromPotOnly ? "Uitgave uit spaarpot" : "Uitgave"
        case .toPot:
            symbol = "tray.and.arrow.down.fill"
            color = Theme.accent
            kindText = "Inleg in spaarpot"
        case .toHolding:
            symbol = "chart.line.uptrend.xyaxis"
            color = Theme.accent
            kindText = "Inleg in belegging"
        case .interest:
            symbol = "percent"
            color = Theme.positive
            kindText = "Rente op spaarpot"
        case .bankEntry:
            symbol = "building.columns.fill"
            color = shown < 0 ? Theme.negative : (shown > 0 ? Theme.positive : Theme.accent)
            kindText = "Boeking op je rekening"
        }
    }

    /// "+ € 3.000" of "− € 1.000"; rente onder de 10 euro met centen ("+ € 1,25").
    var amountText: String {
        isInterest ? CashflowText.signedInterest(amount) : CashflowText.signed(amount)
    }
}

/// Eén regel met een gebeurtenis: icoon, titel, soort en bedrag. Een geplande gebeurtenis zegt het met een woord ("gepland").
/// Met `showsDate` staat de datum bij de soort (voor salaris dat vaker dan eens per maand binnenkomt).
struct DayEventRow: View {
    let event: DayEvent
    var showsDate = false
    var showsChevron = false

    private var caption: String {
        var parts = [DayEventStyle(event).kindText]
        if showsDate { parts.append(DayText.short(event.date)) }
        if event.isPlanned { parts.append("gepland") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let style = DayEventStyle(event)
        HStack(spacing: 10) {
            SymbolBadge(symbol: style.symbol, color: style.color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Text(style.amountText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(style.color)
                .contentTransition(.numericText())
                .layoutPriority(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .animated(by: style.amountText)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - De cijfers van één dag

/// Binnen, eruit en overgeschreven van één dag. Het teken laat zien welke kant het opgaat; "Overgeschreven" staat er alleen
/// als er die dag iets naar spaarpotten of beleggingen gaat (of terug naar de bank).
struct DayFlowTiles: View {
    let day: DayTotals

    var body: some View {
        let moved = day.totalTransferred
        FigureRow {
            StatTile(title: "Binnen", value: CashflowText.signed(day.inflow),
                     color: day.inflow > 0 ? Theme.positive : Theme.textSecondary)
            StatTile(title: "Eruit", value: CashflowText.signed(-day.outflow),
                     color: day.outflow > 0 ? Theme.negative : Theme.textSecondary)
            if moved != 0 {
                StatTile(title: moved > 0 ? "Overgeschreven" : "Teruggeboekt", value: Fmt.euro(abs(moved)),
                         color: Theme.accent)
            }
        }
    }
}

/// Het saldo van de bankrekening en van de spaarpotten aan het eind van een dag, en wat er die dag nog te verdelen is.
/// Precies de waarden van `DayTotals`, in de sectie van de dag op Dag voor dag. Bij het saldo staat ook het saldo aan het begin
/// van de dag, zodat de dag sluit: begin + binnen − eruit − overgeschreven = eind.
struct DayBalanceRows: View {
    let day: DayTotals
    var showsBank = true
    var showsPots = true
    var showsRemaining = true

    private func caption(opening: Double?) -> String {
        guard let opening else { return "Aan het eind van de dag" }
        return "Aan het eind van de dag · begin \(Fmt.euro(opening))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsBank {
                bankRows
            }
            if showsPots {
                potRows
            }
            if showsRemaining {
                // Opgebouwd over de maand tot en met deze dag: pas op de laatste dag is dit "Nog te verdelen" van de hele maand.
                // Een andere naam voorkomt dat het twee verschillende getallen onder één naam zijn.
                AmountRow(title: "Te verdelen t/m deze dag",
                          value: Fmt.euro(day.remainingSoFar),
                          detail: "Opgebouwd in de maand; het totaal van de maand staat bij Nog te verdelen.",
                          color: day.remainingSoFar < 0 ? Theme.negative : Color.primary)
            }
        }
    }

    @ViewBuilder
    private var bankRows: some View {
        if let balance = day.bankBalance {
            AmountRow(title: "Saldo bankrekening", value: Fmt.euro(balance), detail: caption(opening: day.openingBank),
                      color: balance < 0 ? Theme.negative : Color.primary, bold: true)
        } else {
            AmountRow(title: "Saldo bankrekening", value: "onbekend", color: Theme.textSecondary)
        }
        if let measured = day.measuredBalance {
            AmountRow(title: "Saldo dat je invulde", value: Fmt.euro(measured), detail: "Zo vulde je het zelf in voor deze dag")
            if day.bankCorrection != 0 {
                AmountRow(title: "Verschil met wat de app verwachtte", value: CashflowText.signed(day.bankCorrection),
                          color: day.bankCorrection < 0 ? Theme.negative : Theme.positive)
            }
        }
    }

    @ViewBuilder
    private var potRows: some View {
        AmountRow(title: "Spaarpotten totaal", value: Fmt.euro(day.potsTotal), detail: caption(opening: day.openingPots))
        if day.potEntriesNet != 0 {
            AmountRow(title: "Handmatig op spaarpotten", value: CashflowText.signed(day.potEntriesNet))
        }
    }
}

// MARK: - Waarschuwing: onder nul of onder het minimumsaldo

/// Meldt wanneer het dagsaldo onder nul komt (of onder het minimumsaldo), met de datum. De tekst en de keuze wanneer hij er is
/// komen uit `BankLowPointNote.forMonth` (de dagboekhouding, dezelfde saldi als in de dagsecties). Een melding onder nul heeft
/// een driehoek en de kleur van een tekort, een melding over het minimumsaldo een cirkel en de kleur van een waarschuwing:
/// het symbool en de tekst dragen de betekenis, de kleur versterkt hem.
struct BankLowPointNotice: View {
    let note: BankLowPointNote

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: note.severe ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(note.severe ? Theme.negative : Theme.warning)
                .accessibilityHidden(true)
            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(note.severe ? Theme.negative : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dag voor dag: de maand in cijfers

/// Een regel in een sluitend overzicht: teken, omschrijving en bedrag. Een rij in een lijst; de streep boven het eind komt van
/// de lijst zelf.
struct LedgerLineRow: View {
    let row: CashflowRow
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tone: Color {
        switch row.tone {
        case .neutral: return Color.primary
        case .positive: return Theme.positive
        case .negative: return Theme.negative
        case .accent: return Theme.accent
        }
    }

    private var titleFont: Font {
        switch row.style {
        case .line: return Font.subheadline
        case .detail: return Font.footnote
        case .total: return Font.subheadline.weight(.bold)
        }
    }

    private var amountFont: Font {
        switch row.style {
        case .line: return Font.subheadline.weight(.semibold)
        case .detail: return Font.footnote
        case .total: return Font.subheadline.weight(.bold)
        }
    }

    private var titleColor: Color {
        row.style == .detail ? Theme.textSecondary : Color.primary
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    titleColumn
                    amountView
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleColumn
                    Spacer(minLength: 8)
                    amountView
                }
            }
        }
        .padding(.leading, row.style == .detail ? 22 : 0)
        .accessibilityElement(children: .combine)
    }

    private var titleColumn: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.sign)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                if let note = row.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var amountView: some View {
        if let amount = row.amount {
            Text(row.amountText ?? Fmt.euro(amount))
                .font(amountFont)
                .monospacedDigit()
                .foregroundStyle(row.style == .detail ? Theme.textSecondary : tone)
                .contentTransition(.numericText())
                .animated(by: amount)
        } else {
            Text("onbekend")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// De uitklapper "Zo komt je saldo tot stand": de bankrekening van de maand met begin, wat er binnenkwam, eruit ging en werd
/// overgeschreven, en het eind. Handmatige stortingen, opnames en overboekingen staan er apart bij als ze er zijn. Een sectie
/// van een lijst; dicht tot je hem opent. Dezelfde regels (`CashflowSummary.bankRows`) als voor de herbouw.
struct CashflowBankBlock: View {
    let ledger: MonthLedger
    /// Is er in deze maand ergens een saldo bekend? Een saldo dat pas in een latere maand begint zegt hier niets.
    let hasBalance: Bool
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(CashflowSummary.bankRows(ledger)) { row in
                    LedgerLineRow(row: row)
                }
                notes
                RoundingNote()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zo komt je saldo tot stand")
                        .font(.headline)
                    Text(Fmt.month(ledger.month))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if ledger.openingBank == nil && ledger.closingBank != nil {
            Text("Je saldo is pas later in de maand bekend, dus er is nog geen beginsaldo.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        if !hasBalance {
            Text("Vul je saldo in bij Saldo. Dan rekent de app per dag uit hoeveel je hebt.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// De uitklapper "Zo komen je spaarpotten tot stand": begin, inleg, handmatige boekingen, rente, wat er uit potten is betaald
/// en het eind (`CashflowSummary.potsRows`). Een sectie van een lijst; dicht tot je hem opent.
struct CashflowPotsBlock: View {
    let ledger: MonthLedger
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(CashflowSummary.potsRows(ledger)) { row in
                    LedgerLineRow(row: row)
                }
                Text("Inleg telt mee vanaf de overschrijfdag, rente vanaf de uitbetaaldag en een uitgave uit een pot vanaf de dag van die uitgave.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zo komen je spaarpotten tot stand")
                        .font(.headline)
                    Text(Fmt.month(ledger.month))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// De melding als de bankrekening, de spaarpotten of de maandcijfers niet sluiten, met per afwijking het verschil. Het
/// driehoekje en de woorden zeggen wat er aan de hand is, de kleur versterkt het.
struct CashflowCheckBanner: View {
    let check: LedgerCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("De cijfers sluiten niet", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(check.issues) { issue in
                Text(issue.text)
                    .font(.footnote)
            }
        }
        .foregroundStyle(Theme.negative)
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}
