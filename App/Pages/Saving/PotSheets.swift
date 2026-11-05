import SwiftUI

// De bladen van een spaarpot: geld bewegen (storten, opnemen, saldo aanpassen, overboeken) en de pot maken of bewerken.
// Beide hebben `hasChanges`: met niet-bewaarde invoer is veeg-om-te-sluiten uit en vraagt "Annuleer" om bevestiging.

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

// MARK: - Geld bewegen

/// Storten, opnemen, het saldo aanpassen en overboeken. Bij opnemen en storten kies je waar het geld heen gaat of vandaan komt
/// (`MoneyEnd`): buiten je overzicht (zoals Opnemen altijd deed), de bankrekening of een andere spaarpot. De teksten en de keuzes
/// staan in `PotMoveText`, de boekingen in `FinanceData.withdraw` en `deposit`.
struct PotEntrySheet: View {
    let pot: Pot
    let action: PotAction

    @Environment(AppStore.self) private var store
    @State private var amount = 0.0
    @State private var note = ""
    @State private var targetID: UUID?
    /// Waar het geld heen gaat (opnemen) of vandaan komt (storten). Standaard buiten je overzicht: wat Opnemen altijd deed.
    @State private var end: MoneyEnd = .outside
    /// De beginwaarden van het formulier, om te weten of er iets is veranderd.
    @State private var startAmount = 0.0
    @State private var startTarget: UUID?

    /// `end` en `amount` zijn wat het blad ingevuld opent (voor de voorbeelden); de gebruiker kiest zelf verder.
    init(pot: Pot, action: PotAction, end: MoneyEnd = .outside, amount: Double = 0) {
        self.pot = pot
        self.action = action
        _end = State(initialValue: end)
        _amount = State(initialValue: amount)
    }

    private var others: [Pot] { store.data.pots.filter { $0.id != pot.id } }

    private var hasChanges: Bool {
        amount != startAmount || !note.isEmpty || end != .outside || targetID != startTarget
    }

    /// Opnemen of storten: de acties met een bestemming of herkomst.
    private var movesMoney: Bool { action == .deposit || action == .withdraw }

    private var direction: PotMoveDirection { action == .deposit ? .deposit : .withdraw }

    var body: some View {
        let balance = store.data.potBalanceNow(pot.id, current: store.now, today: store.today)
        SheetScaffold(title: action.title, canSave: canSave(balance: balance), hasChanges: hasChanges, onSave: { save() }) {
            Section {
                fields
            } header: {
                Text("Huidig saldo \(Fmt.euro(balance))")
            } footer: {
                entryFooter
            }
        }
        .onAppear {
            if action == .setBalance {
                amount = balance
                startAmount = balance
            }
            if targetID == nil {
                targetID = others.first?.id
                startTarget = targetID
            }
        }
    }

    /// Onder het formulier: bij "Saldo aanpassen" waar het verschil heen gaat, bij opnemen en storten wat er met het bedrag
    /// gebeurt (en dat het banksaldo nog niet bekend is), en bij een startdatum die nog moet komen de waarschuwing dat wat je nu
    /// invult ervoor valt en niet meetelt.
    @ViewBuilder
    private var entryFooter: some View {
        let warning = StartDateText.entryBeforeStartWarning(store.data, at: store.today)
        let move = moveFooter
        let bank = bankUnknownNote
        if action == .setBalance || warning != nil || move != nil || bank != nil {
            VStack(alignment: .leading, spacing: 6) {
                if action == .setBalance {
                    Text("Het verschil wordt als correctie in de geschiedenis gezet.")
                }
                if let move {
                    Text(move)
                }
                if let bank {
                    MonthWarningLine(text: bank)
                }
                if let warning {
                    MonthWarningLine(text: warning)
                }
            }
        }
    }

    /// Wat er met het bedrag gebeurt, zodra er een bedrag is (`PotMoveText.footer`).
    private var moveFooter: String? {
        guard movesMoney, amount > 0 else { return nil }
        return PotMoveText.footer(direction, end: end, amount: amount, in: store.data)
    }

    /// De bankrekening als bron of bestemming terwijl het saldo nog niet is ingevuld: de boeking begint dan het saldo. Bij storten
    /// uit de bank gaat er geld af, dus staat het bedrag er met een min.
    private var bankUnknownNote: String? {
        guard movesMoney, amount > 0, end == .bank,
              !store.data.hasBankBalanceNow(current: store.now, today: store.today) else { return nil }
        return PotMoveText.bankUnknownNote(amount: action == .withdraw ? amount : -amount)
    }

    @ViewBuilder
    private var fields: some View {
        switch action {
        case .deposit, .withdraw:
            NumberRow(title: "Bedrag", value: $amount)
            endPicker
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
    }

    /// "Waar gaat het naartoe?" bij opnemen en "Waar komt het vandaan?" bij storten. Bij storten uit een andere pot staat het saldo van
    /// die pot erbij, want meer dan dat saldo kan er niet uit.
    private var endPicker: some View {
        Picker(PotMoveText.question(direction), selection: $end) {
            ForEach(PotMoveText.choices(excluding: pot.id, in: store.data), id: \.self) { choice in
                Text(choiceTitle(choice)).tag(choice)
            }
        }
    }

    private func choiceTitle(_ choice: MoneyEnd) -> String {
        let title = PotMoveText.title(choice, in: store.data)
        guard direction == .deposit, case .pot(let sourceID) = choice else { return title }
        let balance = store.data.potBalanceNow(sourceID, current: store.now, today: store.today)
        return title + " · " + Fmt.euro(balance)
    }

    private func canSave(balance: Double) -> Bool {
        switch action {
        case .deposit:
            guard amount > 0 else { return false }
            // Uit een andere pot kan er hoogstens zijn saldo uit.
            if case .pot(let sourceID) = end {
                let sourceBalance = store.data.potBalanceNow(sourceID, current: store.now, today: store.today)
                return amount <= sourceBalance + 0.005
            }
            return true
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
        let today = store.today
        let target = targetID
        let chosen = end
        switch action {
        case .deposit:
            store.mutate { $0.deposit(toPot: id, amount: a, from: chosen, note: n) }
        case .withdraw:
            store.mutate { $0.withdraw(fromPot: id, amount: a, to: chosen, note: n) }
        case .setBalance:
            // Het verschil wordt gemeten tegen het saldo van nu: precies het getal dat je zag.
            store.mutate { $0.setPotBalance(id, to: a, current: now, note: n, asOf: today) }
        case .transfer:
            if let target { store.mutate { $0.transfer(from: id, to: target, amount: a) } }
        }
    }
}

// MARK: - Een spaarpot maken of bewerken

struct PotEditSheet: View {
    let pot: Pot?

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded = false
    /// De waarden vlak na het laden, om te weten of er iets is veranderd.
    @State private var loadedSignature: String?
    /// Vaste id voor een nieuwe pot, zodat de voorvertoning van de rente en het bewaren dezelfde pot zijn.
    @State private var draftID = UUID()
    @State private var name = ""
    @State private var symbol = "banknote"
    @State private var colorIndex = 0
    @State private var goal: Double?
    @State private var goalDate: Date?
    @State private var monthly = 0.0
    @State private var opening = 0.0
    @State private var transferDay: Int?
    // Inleg: een vast bedrag (`monthly`) of een percentage van het inkomen (0...100, twee decimalen).
    @State private var mode: ContributionMode = .fixed
    @State private var percent = 0.0
    @State private var basis: IncomeBasis = .salary
    /// Bij een percentage: het vaste bedrag dat er elke maand bovenop komt.
    @State private var extra = 0.0
    /// Extra overschrijfdata van de standaardinleg: delen die op een eigen dag overgaan.
    @State private var parts: [TransferPart] = []
    // Rente
    @State private var rate = 0.0
    @State private var payout: InterestPayout = .yearly
    @State private var payoutDay = 1
    @State private var payoutMonth = 1

    /// Wat de voorvertoning van de rente laat zien.
    private struct InterestPreview {
        var text: String
        var isActive: Bool
        /// Melding als er door deze wijziging rente uit eerdere maanden wordt bijgeschreven.
        var catchUp: String?
    }

    private var rateIsValid: Bool {
        rate.isFinite && rate >= 0 && rate <= 1
    }

    /// Alle invoer in een tekst: gelijk aan die van vlak na het laden betekent dat er niets is veranderd.
    private var signature: String {
        let fields: [String] = [
            name, symbol, String(colorIndex), String(describing: goal), String(describing: goalDate),
            String(monthly), String(opening), String(describing: transferDay), String(describing: mode),
            String(percent), String(describing: basis), String(rate), String(describing: payout),
            String(payoutDay), String(payoutMonth), String(extra), TransferPartsOverview.signature(parts)
        ]
        return fields.joined(separator: "|")
    }

    private var hasChanges: Bool {
        guard let loadedSignature else { return false }
        return loadedSignature != signature
    }

    var body: some View {
        SheetScaffold(title: pot == nil ? "Nieuwe spaarpot" : "Spaarpot bewerken",
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && rateIsValid,
                      hasChanges: hasChanges,
                      onSave: { save() }) {
            nameSection
            appearanceSection
            goalSection
            moneySection
            transferPartsSection
            interestSection
        }
        .onAppear { load() }
    }

    // MARK: Naam, uiterlijk en doel

    private var nameSection: some View {
        Section("Naam") {
            TextField("Bijvoorbeeld Vakantie", text: $name)
        }
    }

    private var appearanceSection: some View {
        Section("Uiterlijk") {
            SymbolChoiceRow(symbol: $symbol, color: Theme.color(colorIndex))
            ColorChoiceRow(index: $colorIndex)
        }
    }

    private var goalSection: some View {
        Section {
            OptionalNumberRow(title: "Doelbedrag", value: $goal, defaultValue: 1000)
            OptionalDateRow(title: "Streefdatum", date: $goalDate)
        } header: {
            Text("Doel")
        } footer: {
            Text("Met een doelbedrag laat de app zien hoe ver je bent en wanneer je er bent.")
        }
    }

    // MARK: Geld

    private var moneySection: some View {
        Section {
            contributionFields
            Toggle("Eigen overschrijfdag", isOn: softly(Binding(
                get: { transferDay != nil },
                set: { on in transferDay = on ? store.data.salaryDay(in: store.now) : nil }
            )))
            if let day = transferDay {
                Stepper(value: Binding(get: { day }, set: { transferDay = $0 }), in: 1...31) {
                    HStack {
                        Text("Overschrijfdag")
                        Spacer()
                        Text(PotFormat.dayName(day)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if pot == nil {
                NumberRow(title: "Beginsaldo", value: $opening)
            }
        } header: {
            Text("Geld")
        } footer: {
            moneyFooter
        }
    }

    private var moneyFooter: some View {
        let d = store.data
        let payDay = PotFormat.dayName(d.salaryDay(in: store.now))
        // Bij een salaris om de zoveel weken of dagen is "de salarisdag" de eerste uitbetaling van de maand.
        let payText = d.salary.isMonthly ? "je salarisdag (\(payDay))" : "de eerste salarisdag van de maand (\(payDay))"
        return VStack(alignment: .leading, spacing: 6) {
            if mode == .percentage {
                Text("Een percentage rekent over het inkomen van die maand: gaat je salaris omhoog, dan gaat de inleg vanzelf mee. In je verdeling kun je het percentage per maand aanpassen.")
            } else {
                Text("De standaard inleg komt elke maand in je verdeling; die kun je per maand aanpassen.")
            }
            Text("Op de overschrijfdag gaat de inleg naar de pot en telt hij mee in het saldo. Zonder eigen dag is dat \(payText). Een verdeling die je voor één maand maakt, kan een eigen dag hebben; die gaat voor.")
            if let overview = partsOverview {
                Text(overview)
            }
        }
    }

    // MARK: Extra overschrijfdagen

    /// De dag waarop de rest van de inleg wordt overgeschreven: je eigen dag voor deze pot, anders je salarisdag.
    private var standardTransferDay: Int {
        min(transferDay ?? store.data.salaryDay(in: store.now), store.now.dayCount)
    }

    /// De inleg van de lopende maand in centen zoals het concept hem nu geeft, voor de delen en hun waarschuwing.
    private var draftTotalCents: Int {
        store.data.rawCents(of: draftPot().contributionRule, in: store.now)
    }

    /// "Overschrijving: € 40 op de 10e en € 85 op de 25e", zodra er delen zijn en een inleg om te verdelen.
    private var partsOverview: String? {
        TransferPartsOverview.line(parts: parts, totalCents: draftTotalCents, standardDay: standardTransferDay, month: store.now)
    }

    private var transferPartsSection: some View {
        StandardTransferPartsSection(parts: $parts, standardDay: standardTransferDay, totalCents: draftTotalCents)
    }

    // MARK: Inleg

    /// De inleg: een vast bedrag of een percentage van je inkomen, met de grondslag. Wat het percentage in euro's oplevert
    /// komt uit de rekenmotor (`ContributionPreview`), precies zoals de verdeling het straks uitrekent.
    @ViewBuilder
    private var contributionFields: some View {
        let preview: ContributionPreview.Result? = mode == .percentage
            ? ContributionPreview.resolve(store.data, percent: percent, basis: basis, extra: extra, month: store.now)
            : nil
        ContributionFields(mode: modeBinding, amount: $monthly, percent: $percent, basis: $basis,
                           amountTitle: "Standaard inleg per maand", percentTitle: "Percentage van je inkomen",
                           resolvedAmount: preview?.amount, resolvedNote: preview?.note, footnote: preview?.footnote,
                           subject: name, extra: mode == .percentage ? $extra : nil)
        if mode == .percentage {
            // Het extra bedrag komt bovenop het percentage; de som staat hierboven bij "=".
            MonthExplanation(text: ExtraAmountText.footer)
            // Samen meer dan 100% van je inkomen, of meer dan er te verdelen is: de motor meldt het al voor je bewaart.
            ForEach(ContributionPreview.warnings(store.data, pot: draftPot(), month: store.now), id: \.message) { warning in
                AllocationWarningLabel(warning: warning)
                    .transition(.opacity)
            }
        }
    }

    private var modeBinding: Binding<ContributionMode> {
        Binding(
            get: { mode },
            set: { newMode in
                withAnimation(reduceMotion ? nil : Theme.motion) {
                    prefill(for: newMode)
                    mode = newMode
                }
            }
        )
    }

    /// Bij een andere inlegwijze begint het veld bij wat de inleg nu is: een bedrag wordt het percentage van je salaris dat
    /// erbij hoort, een percentage (met zijn extra bedrag) wordt het bedrag dat het nu oplevert. Zo verspringt de inleg niet. De
    /// rekenmotor doet de omrekening (`percent(forAmount:)`, `percentAmount`). Een extra bedrag hoort bij een percentage: bij een
    /// vast bedrag is het al in het bedrag opgenomen, en een nieuw percentage begint zonder.
    private func prefill(for newMode: ContributionMode) {
        let d = store.data
        let month = store.now
        switch newMode {
        case .percentage:
            if percent == 0, monthly > 0, let start = d.percent(forAmount: monthly, of: basis, in: month) { percent = start }
            extra = 0
        case .fixed:
            if monthly == 0, percent > 0 || extra > 0 { monthly = d.percentAmount(percent, of: basis, extra: extra, in: month) }
            extra = 0
        }
    }

    // MARK: Rente

    @ViewBuilder
    private var interestSection: some View {
        let preview = interestPreview()
        Section {
            NumberRow(title: "Rente per jaar", value: $rate, unit: .percent)
            Picker("Uitbetaling", selection: payoutBinding) {
                ForEach(InterestPayout.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Stepper(value: $payoutDay, in: 1...31) {
                HStack {
                    Text("Dag van de maand")
                    Spacer()
                    Text("\(payoutDay)").monospacedDigit().foregroundStyle(Theme.textSecondary)
                }
            }
            if payout != .monthly {
                // Bij een kwartaal of half jaar kies je de eerste uitbetaling van het jaar (de rest volgt): januari t/m maart of juni.
                Picker(payout == .yearly ? "Maand van uitbetaling" : "Eerste uitbetaling in", selection: $payoutMonth) {
                    ForEach(PotFormat.firstMonthChoices(for: payout), id: \.self) { number in
                        Text(PotFormat.monthName(number)).tag(number)
                    }
                }
            }
            previewRow(preview)
        } header: {
            Text("Rente")
        } footer: {
            interestFooter(preview)
        }
    }

    private func previewRow(_ preview: InterestPreview) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: preview.isActive ? "calendar.badge.clock" : "percent")
                .foregroundStyle(preview.isActive ? Theme.positive : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(preview.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .animated(by: preview.text, quick: true)
    }

    private func interestFooter(_ preview: InterestPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !rateIsValid {
                Text("Vul een rente tussen 0% en 100% in.").foregroundStyle(Theme.negative)
            } else if rate > 0 {
                Text(PotFormat.schedule(payout, firstMonth: payoutMonth, day: payoutDay))
                Text("De app schrijft de rente zelf bij op die dag. Het bedrag is een verwachting: per maand telt een twaalfde van het percentage over je saldo op de eerste van de maand.")
                if let catchUp = preview.catchUp {
                    Text(catchUp).foregroundStyle(Theme.warning)
                }
            } else {
                Text("Vul een percentage in om rente te krijgen. De app schrijft de rente dan zelf bij op de dag die je kiest.")
            }
        }
    }

    /// Verwachte volgende uitbetaling met de instellingen zoals ze nu in het scherm staan.
    private func interestPreview() -> InterestPreview {
        guard rateIsValid else {
            return InterestPreview(text: "Controleer de rente", isActive: false, catchUp: nil)
        }
        guard rate > 0 else {
            return InterestPreview(text: "Geen rente ingesteld", isActive: false, catchUp: nil)
        }
        let today = store.today
        let draft = draftPot()
        // Reken op een kopie van de gegevens, na precies dezelfde stappen als bij bewaren.
        var trial = store.data
        commit(draft, to: &trial, now: store.now, today: today)
        guard let next = trial.nextInterestPayment(for: draft.id, asOf: today) else {
            return InterestPreview(text: "Volgende uitbetaling: zodra er saldo op de pot staat", isActive: false, catchUp: nil)
        }
        return InterestPreview(text: "Volgende uitbetaling: " + PotFormat.nextPayment(next),
                               isActive: true,
                               catchUp: catchUpNote(trial: trial, draft: draft, today: today))
    }

    /// Een pot die al langer bestaat krijgt de rente ook over eerdere maanden. Laat dat vooraf weten.
    private func catchUpNote(trial: FinanceData, draft: Pot, today: Date) -> String? {
        guard let existing = pot else { return nil }
        let from = existing.startMonth.firstDay
        // Alles wat nu al aan de beurt was (opgeslagen of verwacht), tegenover wat er na bewaren aan de beurt is.
        // In `trial` is de rente al bijgeschreven, daarom telt hier niet mee of een uitbetaling nog "verwacht" is.
        // Per kalenderdag, zoals het saldo: een uitbetaling van vandaag telt al mee (ook voor 12:00).
        let limit = DayMath.planLimit(for: today)
        let before = store.data.interestPayments(for: existing.id, from: from, to: today, asOf: today)
            .filter { $0.date < limit }
        let after = trial.interestPayments(for: draft.id, from: from, to: today, asOf: today)
            .filter { $0.date < limit }
        let known = Set(before.map { $0.id })
        let added = after.filter { !known.contains($0.id) }
        guard !added.isEmpty else { return nil }
        let cents = CentsMath.sum(added.map { CentsMath.int($0.amount) })
        let count = added.count == 1 ? "1 uitbetaling" : "\(added.count) uitbetalingen"
        return "Deze pot bestaat al langer. De app schrijft daarom ook de rente van eerdere maanden bij: \(count), samen ongeveer \(PotFormat.interest(CentsMath.value(cents)))."
    }

    // MARK: Laden en bewaren

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let pot {
            name = pot.name
            symbol = pot.symbol
            colorIndex = pot.colorIndex
            goal = pot.goalAmount
            goalDate = pot.goalDate
            monthly = pot.monthlyContribution
            mode = pot.contributionMode
            percent = pot.contributionPercent
            basis = pot.contributionBasis
            extra = pot.contributionExtra
            parts = pot.extraTransfers
            transferDay = pot.transferDay
            rate = pot.interestRate
            payout = pot.interestPayout
            payoutDay = min(max(pot.interestPayoutDay, 1), 31)
            payoutMonth = PotFormat.firstMonth(pot.interestPayoutMonth, for: pot.interestPayout)
        } else {
            colorIndex = store.data.pots.count % Theme.palette.count
        }
        loadedSignature = signature
    }

    /// De pot zoals hij na bewaren is: voor de voorvertoning en om te bewaren.
    private func draftPot() -> Pot {
        var p: Pot
        if let existing = pot {
            p = existing
        } else {
            p = Pot(name: name, symbol: symbol, colorIndex: colorIndex,
                    goalAmount: goal, goalDate: goalDate,
                    monthlyContribution: monthly.cents, startMonth: store.now)
            p.id = draftID
        }
        p.name = name.trimmingCharacters(in: .whitespaces)
        p.symbol = symbol
        p.colorIndex = colorIndex
        p.goalAmount = goal
        p.goalDate = goalDate
        p.monthlyContribution = monthly.cents
        p.contributionMode = mode
        // Het percentage zoals de rekenmotor het gebruikt: 0...100 op twee decimalen.
        p.contributionPercent = AllocationMath.cleanPercent(percent)
        p.contributionBasis = basis
        // Het extra bedrag hoort bij een percentage (bij een vast bedrag is het al het totaal), op hele centen.
        p.contributionExtra = mode == .percentage ? AllocationMath.cleanExtra(extra) : 0
        p.extraTransfers = TransferMath.normalized(parts)
        p.transferDay = transferDay
        // Afgerond op 0,001%, zodat een getypt percentage geen afrondruis meekrijgt.
        p.interestRate = (rate * 100_000).rounded() / 100_000
        p.interestPayout = payout
        p.interestPayoutDay = payoutDay
        p.interestPayoutMonth = PotFormat.firstMonth(payoutMonth, for: payout)
        return p
    }

    private func save() {
        let saved = draftPot()
        let now = store.now
        let today = store.today
        store.mutate { commit(saved, to: &$0, now: now, today: today) }
    }

    /// De stappen van bewaren, ook gebruikt door de voorvertoning van de rente.
    private func commit(_ draft: Pot, to data: inout FinanceData, now: YearMonth, today: Date) {
        if pot == nil {
            data.addPot(draft, openingBalance: opening)
        } else {
            // Eerst de rente vastleggen die al aan de beurt was, met de oude instellingen. Anders wordt die achteraf
            // met het nieuwe percentage, de nieuwe dag of de nieuwe inleg berekend, terwijl in die maanden de oude gold.
            data.applyDueInterest(upTo: today)
            data.updatePot(draft, current: now)
        }
        // Wat na deze wijziging aan de beurt is (bijvoorbeeld bij rente die je net hebt aangezet) schrijft de app nu bij.
        data.applyDueInterest(upTo: today)
    }

    /// Bij een andere uitbetaling blijft de eerste uitbetaalmaand binnen het nieuwe ritme.
    private var payoutBinding: Binding<InterestPayout> {
        Binding(
            get: { payout },
            set: { newValue in
                withAnimation(reduceMotion ? nil : Theme.motion) {
                    payout = newValue
                    payoutMonth = PotFormat.firstMonth(payoutMonth, for: newValue)
                }
            }
        )
    }

    /// Dezelfde binding, maar een wijziging beweegt zacht (rijen die verschijnen of verdwijnen), tenzij Verlaag beweging aan staat.
    private func softly<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                withAnimation(reduceMotion ? nil : Theme.motion) { binding.wrappedValue = newValue }
            }
        )
    }
}
