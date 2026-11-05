import SwiftUI

// De bouwstenen van de pagina Verdelen (DistributePage.swift): één rij voor een spaarpot, een belegging of de bankrekening met haar
// invoer (een bedrag, of een percentage met een extra bedrag), de afwijking van de standaard en, voor een pot of belegging, de extra
// overschrijfdagen. De logica zonder SwiftUI staat in App/UI/SavingsDisplay.swift (`AllocationEdit`, `DistributeText`) en
// App/UI/DistributionText.swift (`ExtraAmountText`, `TransferPartsText`, `BankShareText`), zodat de tests in CoreTests haar
// meedraaien. Deze views zijn invoer: bedragen, dagen en teksten komen uit de rekenmotor en die hulpen.

// MARK: - Eén spaarpot, belegging of de bankrekening

/// Eén rij op de pagina Verdelen: de inleg van deze maand als vast bedrag of als percentage van het inkomen met een extra bedrag
/// erbij (per maand te overschrijven), met wat het percentage in euro's oplevert, de overschrijfdag en de extra overschrijfdagen
/// (alleen bij een pot of belegging) en de standaard. De bankrekening is dezelfde rij met `movesMoney: false`: er wordt niets
/// overgeschreven, dus geen overschrijfdagen en geen negatief bedrag.
struct MonthAllocationRow: View {
    let id: UUID
    let name: String
    let symbol: String
    let color: Color
    let month: YearMonth
    /// "Wordt overgeschreven op de 25e · salarisdag" (de pagina stelt dit samen uit de rekenmotor).
    let caption: String
    /// Een bedrag onder nul betekent geld terug naar de rekening: dat kan bij een spaarpot of belegging, niet bij de bankrekening.
    var allowsNegativeAmount = true
    /// Gaat er geld naar een pot of belegging? Dan horen de extra overschrijfdagen en de melding bij een startdatum erbij.
    var movesMoney = true
    /// Wat VoiceOver na de naam leest ("Blijft op je rekening"). nil = alleen de naam.
    var spokenSubtitle: String? = nil

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let d = store.data
        let effective = d.effectiveAllocation(id, in: month)
        let differs = AllocationEdit.differsFromStandard(d, id: id, month: month)
        VStack(alignment: .leading, spacing: 10) {
            header(differs: differs)
            ContributionFields(mode: modeBinding, amount: amountBinding, percent: percentBinding, basis: basisBinding,
                               allowsNegativeAmount: allowsNegativeAmount,
                               resolvedAmount: effective.rule.isPercent ? effective.amount : nil,
                               resolvedNote: effective.rule.isPercent ? effective.rule.summary : nil,
                               footnote: noIncomeNote(d, rule: effective.rule), subject: name,
                               extra: extraBinding, extraTitle: ExtraAmountText.title)
            extraBreakdown(d, rule: effective.rule)
            MonthExplanation(text: caption)
            if movesMoney {
                transferSection(d, rule: effective.rule)
            }
            if differs {
                standardRow(d)
            }
        }
        .padding(12)
        .tile()
    }

    // MARK: Kop

    /// De naam met het symbool en, als deze maand afwijkt van de standaard, "Afwijkend". Eén element voor VoiceOver.
    private func header(differs: Bool) -> some View {
        HStack(spacing: 10) {
            SymbolBadge(symbol: symbol, color: color, size: 32)
            Text(name)
                .font(.body.weight(.semibold))
            Spacer(minLength: 6)
            if differs {
                Text("Afwijkend")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warning)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenHeader(differs: differs))
    }

    /// "Bankrekening, blijft op je rekening" of "Vakantie, afwijkend".
    private func spokenHeader(differs: Bool) -> String {
        var parts = [name]
        if let spokenSubtitle {
            parts.append(spokenSubtitle.lowercased())
        }
        if differs {
            parts.append("afwijkend")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Bindings naar de rekenmotor

    private var modeBinding: Binding<ContributionMode> {
        Binding(get: { store.data.allocationRule(id, in: month).isPercent ? ContributionMode.percentage : ContributionMode.fixed },
                set: { newMode in
                    withAnimation(reduceMotion ? nil : Theme.motion) {
                        store.mutate { AllocationEdit.setMode(&$0, id: id, month: month, to: newMode) }
                    }
                })
    }

    private var amountBinding: Binding<Double> {
        Binding(get: {
            // Wat de regel zegt, ook als de overschrijving niet meetelt (zie `transferSection`): anders sprong het veld terug naar 0.
            if case .amount(let value) = store.data.allocationRule(id, in: month) { return CentsMath.value(CentsMath.int(value)) }
            return store.data.allocation(id, in: month)
        }, set: { value in
            store.mutate { AllocationEdit.setAmount(&$0, id: id, month: month, amount: value) }
        })
    }

    private var percentBinding: Binding<Double> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.percent }
            return 0
        }, set: { value in
            store.mutate { AllocationEdit.setPercent(&$0, id: id, month: month, percent: value) }
        })
    }

    private var basisBinding: Binding<IncomeBasis> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.basis }
            return IncomeBasis.salary
        }, set: { newBasis in
            withAnimation(reduceMotion ? nil : Theme.motion) {
                store.mutate { AllocationEdit.setBasis(&$0, id: id, month: month, to: newBasis) }
            }
        })
    }

    /// Het extra bedrag bovenop het percentage van deze maand (het veld staat er alleen bij de inlegwijze Percentage).
    private var extraBinding: Binding<Double> {
        Binding(get: {
            if case .percent(let rule) = store.data.allocationRule(id, in: month) { return rule.extra }
            return 0
        }, set: { value in
            store.mutate { AllocationEdit.setExtra(&$0, id: id, month: month, extra: value) }
        })
    }

    // MARK: Uitleg onder de invoer

    /// Een percentage van niets is niets: zeg dat, anders lijkt het veld stuk. De tekst komt van `ContributionPreview` (hetzelfde als
    /// in het blad van een spaarpot): zonder inkomen blijft alleen het extra bedrag over.
    private func noIncomeNote(_ d: FinanceData, rule: AllocationRule) -> String? {
        guard case .percent(let percent) = rule, d.incomeBases(in: month).cents(for: percent.basis) == 0 else { return nil }
        return ContributionPreview.resolve(d, percent: percent.percent, basis: percent.basis, extra: percent.extra, month: month).footnote
    }

    /// Met een extra bedrag: hoe het bedrag van de maand is opgebouwd ("€ 300 uit het percentage plus € 50 extra").
    @ViewBuilder
    private func extraBreakdown(_ d: FinanceData, rule: AllocationRule) -> some View {
        if case .percent(let percent) = rule,
           let text = ExtraAmountText.breakdown(percentAmount: d.percentAmount(percent.percent, of: percent.basis, in: month),
                                                extra: percent.extra) {
            MonthExplanation(text: text)
        }
    }

    // MARK: Overschrijven

    /// Valt (een deel van) de inleg vóór de startdag, dan telt dat niet mee: zeg dat bij de rij. Daaronder de extra overschrijfdagen,
    /// alleen vanaf de startmaand en bij een bedrag boven nul.
    @ViewBuilder
    private func transferSection(_ d: FinanceData, rule: AllocationRule) -> some View {
        if let note = TransferPartsText.beforeStartNote(d.uncountedTransferSlices(for: id, in: month)) {
            MonthWarningLine(text: note)
        }
        if month >= d.startMonth, d.rawCents(of: rule, in: month) > 0 {
            DistributePartsGroup(id: id, month: month)
        }
    }

    // MARK: Standaard

    /// "Standaard: 10% van je salaris plus € 25 met € 40 op de 10e": de standaardregel met de standaarddelen.
    private func standardText(_ d: FinanceData) -> String {
        let rule = d.defaultAllocationRule(id, in: month)?.summary ?? Fmt.euro(0)
        guard let parts = TransferPartsText.standardParts(d.standardTransferParts(of: id)) else { return "Standaard: \(rule)" }
        return "Standaard: \(rule) \(parts)"
    }

    /// Wat de standaard is, met de knoppen om daarnaar terug te gaan of van deze maand de standaard te maken.
    @ViewBuilder
    private func standardRow(_ d: FinanceData) -> some View {
        MonthExplanation(text: standardText(d))
        ActionGroup {
            ActionButton(title: TransferPartsText.resetTitle, symbol: "arrow.counterclockwise") {
                withAnimation(reduceMotion ? nil : Theme.motion) {
                    store.mutate { AllocationEdit.resetToStandard(&$0, id: id, month: month) }
                }
            }
            // Van een maand in het verleden maak je geen standaard: dat gaat over wat er vanaf nu gebeurt.
            if month >= store.now {
                ActionButton(title: TransferPartsText.makeStandardTitle, symbol: "pin") {
                    let current = store.now
                    withAnimation(reduceMotion ? nil : Theme.motion) {
                        store.mutate { AllocationEdit.makeStandard(&$0, id: id, month: month, current: current) }
                    }
                }
            }
        }
    }
}

// MARK: - Extra overschrijfdagen

/// De uitklapper "Extra overschrijfdagen" van een pot of belegging in één maand: dicht ziet hij er als samenvatting uit ("Alles op de
/// 25e" of "€ 50 op de 10e en € 150 op de 25e"), open staat de lijst met delen (`TransferPartsEditor`). De editor werkt op een concept
/// (`draft`): een rij met bedrag 0 bestaat niet in de opslag (`TransferMath.normalized` laat haar weg), dus zou ze verdwijnen terwijl
/// je typt. Elke wijziging gaat meteen naar de opslag (`setTransferParts`); een wijziging van buiten (een andere maand, "Terug naar
/// standaard") vervangt het concept alleen als de opgeslagen lijst anders is (`TransferPartsDraft.displayed`).
struct DistributePartsGroup: View {
    let id: UUID
    let month: YearMonth

    @Environment(AppStore.self) private var store
    @State private var expanded: Bool
    @State private var draft: [TransferPart] = []

    init(id: UUID, month: YearMonth, startsExpanded: Bool = false) {
        self.id = id
        self.month = month
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        let d = store.data
        let stored = d.transferParts(for: id, in: month)
        let standardDay = d.transferDay(for: id, in: month)
        let summary = TransferPartsText.summary(slices: d.transferSlices(for: id, in: month), standardDay: standardDay)
        DisclosureGroup(isExpanded: $expanded) {
            TransferPartsEditor(parts: partsBinding(stored: stored), standardDay: standardDay,
                                totalCents: d.rawCents(of: d.allocationRule(id, in: month), in: month))
                .padding(.top, 8)
        } label: {
            label(summary: summary)
        }
        .onAppear { draft = stored }
        .onChange(of: month) { _, newMonth in
            draft = store.data.transferParts(for: id, in: newMonth)
        }
        .onChange(of: stored) { _, newStored in
            draft = TransferPartsDraft.displayed(draft: draft, stored: newStored)
        }
    }

    /// De kop: de titel en de samenvatting. VoiceOver leest de titel en de samenvatting als waarde.
    private func label(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(TransferPartsText.title, systemImage: "calendar.badge.plus")
                .font(.headline)
            Text(summary)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(minHeight: Theme.minTapTarget, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TransferPartsText.title)
        .accessibilityValue(summary)
    }

    /// Wat de editor toont (het concept zolang het gelijk is aan de opslag, anders de opslag) en wat hij bewaart.
    private func partsBinding(stored: [TransferPart]) -> Binding<[TransferPart]> {
        Binding(get: { TransferPartsDraft.displayed(draft: draft, stored: stored) },
                set: { newParts in
                    draft = newParts
                    store.mutate { $0.setTransferParts(id, in: month, parts: newParts) }
                })
    }
}
