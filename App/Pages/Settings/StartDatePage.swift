import SwiftUI

// De pagina Startdatum (`.settings(.startDate)`, een subpagina van Gegevens): kies de dag waarop alles begint. Wat je daarvoor
// invulde telt niet mee, ook al blijft het bewaard (docs/work/plan.md par. 2). Je kunt alleen de startdatum instellen, of alles
// wissen en opnieuw beginnen vanaf die dag; daarna vul je het beginsaldo in van de bankrekening en de spaarpotten. Een gewone pagina
// (geen blad): de bevestiging hangt aan de knop. Alle teksten staan in `StartDateText` (App/UI/StartDateText.swift).

/// Wat dit apparaat voor dit account onthoudt (spaardoel-concept, buffer, uurloon) gaat weg bij "Alles wissen" (Gegevens) en bij "Alles
/// wissen en opnieuw beginnen" (Startdatum).
@MainActor
func clearRememberedChoices(auth: AuthStore, cloud: CloudAccount?) {
    let account = accountPrefsID(auth: auth, cloud: cloud)
    AccountPrefs.clearAll(account: account)
    SavingsGoalDraft.clearStored(account: account)
}

struct StartDatePage: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    /// De gekozen dag in de datumkiezer (nil tot de pagina opent: dan de huidige startdatum of vandaag).
    @State private var chosen: Date?
    @State private var erases = false
    @State private var confirmErase = false
    @State private var notice: String?
    @State private var successCount = 0

    private var chosenDate: Date { chosen ?? store.data.startDate ?? store.today }
    private var chosenDay: CalendarDay { CalendarDay(date: chosenDate) }

    private var chosenBinding: Binding<Date> {
        Binding(get: { chosenDate }, set: { chosen = $0; notice = nil })
    }

    private var erasesBinding: Binding<Bool> {
        Binding(get: { erases }, set: { erases = $0; notice = nil })
    }

    /// Mag de knop iets doen? De huidige startdatum nogmaals instellen niet; alles wissen wel.
    private var canApply: Bool {
        erases || chosenDay != store.data.effectiveStartDay
    }

    var body: some View {
        ListScaffold(title: StartDateText.pageTitle) {
            if let notice {
                SettingsNotice(text: notice, symbol: "checkmark.circle.fill")
            }
            dateSection
            changesSection
            choiceSection
            actionSection
            if let start = store.data.effectiveStartDay {
                StartDateOpeningSection(start: start, onSaved: { show($0) })
            }
        }
        .sensoryFeedback(.success, trigger: successCount)
    }

    private func show(_ text: String) {
        notice = text
        successCount += 1
    }

    // MARK: De datum

    private var dateSection: some View {
        Section {
            Text(StartDateText.summary(for: store.data))
                .frame(maxWidth: .infinity, alignment: .leading)
            DatePicker(StartDateText.pickerTitle, selection: chosenBinding,
                       in: StartDateText.pickerRange(today: store.today), displayedComponents: .date)
                .datePickerStyle(.compact)
                .environment(\.locale, Fmt.locale)
                .frame(minHeight: Theme.minTapTarget)
        } footer: {
            SettingsFootnote(StartDateText.explanation)
        }
    }

    // MARK: Wat verandert er?

    @ViewBuilder
    private var changesSection: some View {
        let counts = StartDateCounts(store.data, before: chosenDay)
        Section {
            if chosenDay == store.data.effectiveStartDay {
                SettingsFootnote(StartDateText.sameDayNote)
            }
            ForEach(StartDateText.countLines(counts)) { line in
                AmountRow(title: line.title, value: "\(line.count)")
            }
            MonthExplanation(text: StartDateText.warning(counts, day: chosenDay))
        } header: {
            SectionHeader("Wat verandert er?")
        }
    }

    // MARK: Hoe

    private var choiceSection: some View {
        Section {
            Picker("Wat wil je doen?", selection: erasesBinding) {
                Text(StartDateText.keepChoice).tag(false)
                Text(StartDateText.eraseChoice).tag(true)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } footer: {
            SettingsFootnote(StartDateText.choiceFootnote(erases: erases))
        }
    }

    // MARK: De knop

    private var actionSection: some View {
        Section {
            ActionButton(title: StartDateText.actionTitle(erases: erases), symbol: erases ? "trash" : "calendar.badge.plus",
                         role: erases ? .destructive : nil, prominent: true, action: apply)
                .disabled(!canApply)
                .listRowBackground(Color.clear)
                .confirmationDialog(StartDateText.eraseTitle(day: chosenDay), isPresented: $confirmErase,
                                    titleVisibility: .visible) {
                    Button(StartDateText.eraseConfirm, role: .destructive) { eraseAndRestart() }
                    Button("Annuleer", role: .cancel) {}
                } message: {
                    Text(StartDateText.eraseMessage(day: chosenDay, cloud: FirebaseConfig.isConfigured))
                }
        }
    }

    private func apply() {
        if erases {
            confirmErase = true
        } else {
            let day = chosenDay
            store.setStart(day)
            show(StartDateText.startSaved(day: day))
        }
    }

    private func eraseAndRestart() {
        let day = chosenDay
        // eraseEverything stempelt de wijziging zelf voor de cloud; wat dit apparaat onthoudt gaat ook weg, zoals bij Alles wissen.
        store.eraseEverything(startingOn: day)
        clearRememberedChoices(auth: auth, cloud: cloud)
        erases = false
        show(StartDateText.restarted(day: day))
    }
}

// MARK: - Beginsaldo

/// Het beginsaldo op de startdag: het saldo van de bankrekening en van elke spaarpot, zoals ze aan het eind van die dag staan, met
/// alles wat die dag al gebeurd is. De velden beginnen bij wat de rekenmotor die dag nu uitrekent; wat je niet aanraakt blijft
/// zoals het was. Opnieuw bewaren vervangt het vorige beginsaldo van die dag.
private struct StartDateOpeningSection: View {
    let start: CalendarDay
    let onSaved: (String) -> Void
    @Environment(AppStore.self) private var store

    @State private var bank = 0.0
    @State private var potValues: [UUID: Double] = [:]
    @State private var bankTouched = false
    @State private var touchedPots: Set<UUID> = []
    /// Voor welke startdag de velden zijn gevuld: een rij die uit beeld en weer in beeld komt vult ze niet opnieuw.
    @State private var seededFor: CalendarDay?

    private var bankBinding: Binding<Double> {
        Binding(get: { bank }, set: { bank = $0; bankTouched = true })
    }

    private func potBinding(_ id: UUID) -> Binding<Double> {
        Binding(get: { potValues[id] ?? 0 },
                set: { potValues[id] = $0; touchedPots.insert(id) })
    }

    private var hasEdits: Bool { bankTouched || !touchedPots.isEmpty }

    var body: some View {
        Section {
            NumberRow(title: StartDateText.bankRowTitle, value: bankBinding, allowsNegative: true)
                .onAppear(perform: seedIfNeeded)
                .onChange(of: start) { _, _ in seed() }
            ForEach(store.data.pots) { pot in
                NumberRow(title: pot.name, value: potBinding(pot.id))
            }
            ActionButton(title: StartDateText.openingSave, symbol: "checkmark", action: save)
                .disabled(!hasEdits)
                .listRowBackground(Color.clear)
        } header: {
            SectionHeader(StartDateText.openingTitle(day: start))
        } footer: {
            SettingsFootnote(StartDateText.openingFootnote)
        }
    }

    private func seedIfNeeded() {
        if seededFor != start { seed() }
    }

    /// Begint bij wat die dag nu uitkomt: het banksaldo (onbekend is 0) en het saldo van elke spaarpot aan het eind van de startdag.
    private func seed() {
        let d = store.data
        let moment = start.date()
        bank = d.bankBalance(on: moment) ?? 0
        var values: [UUID: Double] = [:]
        for pot in d.pots { values[pot.id] = d.potBalance(pot.id, asOf: moment) }
        potValues = values
        bankTouched = false
        touchedPots = []
        seededFor = start
    }

    private func save() {
        var values: [UUID: Double] = [:]
        for id in touchedPots { values[id] = potValues[id] ?? 0 }
        store.setOpeningBalances(on: start, bank: bankTouched ? bank : nil, pots: values)
        seed()
        onSaved(StartDateText.openingSaved)
    }
}

#if DEBUG
// MARK: - Previews

/// Een winkel met voorbeelddata (en naar keuze een startdatum), een router en een lokaal account voor de previews.
@MainActor
private struct StartDatePreviewHost: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var auth: AuthStore
    @State private var cloud = CloudAccount()

    init(startDay: CalendarDay?, sample: Bool) {
        let preview = AppStore(storage: nil)
        if sample { preview.loadSampleData() }
        if let startDay { preview.setStart(startDay) }
        _store = State(initialValue: preview)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyBuddyStartDatePreview", isDirectory: true)
        let defaults = UserDefaults(suiteName: "nl.mybuddy.startdate-preview") ?? UserDefaults.standard
        _auth = State(initialValue: AuthStore(directory: directory, defaults: defaults, iterations: 1))
    }

    var body: some View {
        NavigationStack {
            StartDatePage()
        }
        .environment(store)
        .environment(router)
        .environment(auth)
        .environment(\.cloudAccount, cloud)
    }
}

private func previewStartDay(offset: Int) -> CalendarDay {
    CalendarDay(date: Date()).adding(days: offset)
}

#Preview("Startdatum, niet ingesteld") {
    StartDatePreviewHost(startDay: nil, sample: true)
        .preferredColorScheme(.light)
}

#Preview("Startdatum, ingesteld") {
    StartDatePreviewHost(startDay: previewStartDay(offset: -20), sample: true)
        .preferredColorScheme(.light)
}

#Preview("Startdatum, donker") {
    StartDatePreviewHost(startDay: previewStartDay(offset: -20), sample: true)
        .preferredColorScheme(.dark)
}

#Preview("Startdatum, grote tekst") {
    StartDatePreviewHost(startDay: previewStartDay(offset: -20), sample: true)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Startdatum, lege start") {
    StartDatePreviewHost(startDay: previewStartDay(offset: 5), sample: false)
}
#endif
