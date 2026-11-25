#if DEBUG
import SwiftUI

// Previews van Salaris met het loon per maand en de uren uit de agenda, en van "Loon wijzigen" (docs/work/plan2.md par. 4.6):
// zonder wijzigingen, met twee wijzigingen en "Nu", nieuw, bewerken, uurloon en vast bedrag, donker, grote tekst, een maand in het
// verleden, en uren uit een vaste demo-agenda.

@MainActor
private struct WagePreviewHost<Content: View>: View {
    @State private var store: AppStore
    @State private var router = Router()
    @State private var calendar = WorkCalendarController(source: DemoWorkCalendar())
    private let content: (AppStore) -> Content

    init(changes: Bool = true, fixed: Bool = false, calendarHours: Bool = false,
         @ViewBuilder content: @escaping (AppStore) -> Content) {
        let sample = AppStore(storage: nil)
        sample.loadSampleData()
        let now = sample.now
        sample.mutate { data in
            data.salary.mode = fixed ? .fixed : .hourly
            if fixed { data.salary.fixedMonthly = 2_450 } // wage: voorbeelddata van de preview
            if changes {
                data.setSalaryChange(SalaryChange(from: now.adding(-2), hourlyRate: data.salary.hourlyRate + 0.75, // wage: voorbeelddata
                                                  fixedMonthly: fixed ? 2_550 : nil))
                data.setSalaryChange(SalaryChange(from: now.adding(3), hourlyRate: data.salary.hourlyRate + 1.5, // wage: voorbeelddata
                                                  fixedMonthly: fixed ? 2_650 : nil, hoursPerWeek: 32))
            }
            data.work.hoursSource = calendarHours ? .calendar : .manual
        }
        _store = State(initialValue: sample)
        self.content = content
    }

    var body: some View {
        NavigationStack { content(store) }
            .environment(store)
            .environment(router)
            .environment(calendar)
            .task { await calendar.refresh(into: store, force: true) }
    }
}

#Preview("Salaris, loon per maand") {
    WagePreviewHost { _ in SalaryPage() }
}

#Preview("Salaris, zonder wijzigingen") {
    WagePreviewHost(changes: false) { _ in SalaryPage() }
}

#Preview("Salaris, uren uit agenda") {
    WagePreviewHost(calendarHours: true) { _ in SalaryPage() }
}

#Preview("Salaris, vast bedrag, donker") {
    WagePreviewHost(fixed: true) { _ in SalaryPage() }
        .preferredColorScheme(.dark)
}

#Preview("Loon wijzigen, nieuw") {
    WagePreviewHost(changes: false) { store in WageChangePage(month: store.now.adding(1)) }
}

#Preview("Loon wijzigen, bewerken") {
    WagePreviewHost { store in WageChangePage(month: store.now.adding(3)) }
}

#Preview("Loon wijzigen, verleden") {
    WagePreviewHost { store in WageChangePage(month: store.now.adding(-2)) }
}

#Preview("Loon wijzigen, vast bedrag, grote tekst") {
    WagePreviewHost(fixed: true) { store in WageChangePage(month: store.now.adding(1)) }
        .dynamicTypeSize(.accessibility3)
}
#endif
