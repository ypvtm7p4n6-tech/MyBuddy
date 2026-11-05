import SwiftUI

// De pagina Werkuren (`.settings(.workHours)`): de uren van je salaris uit de iCloud-agenda "werken", met toeslagen, pauzes en
// feestdagen (docs/work/plan.md par. 4.4). Dit is de plaatshouder van de werkuren-Core (`G2V2`): de pagina zelf, met de agenda-adapter
// en de controller, bouwt golf 3A. Alle teksten staan in `WorkText` (App/UI/WorkDisplay.swift).

struct WorkHoursPage: View {
    var body: some View {
        ListScaffold(title: WorkText.pageTitle) {
            Section {
                Text(WorkText.sourceFooter)
            }
        }
    }
}

#if DEBUG
#Preview("Werkuren") {
    NavigationStack {
        WorkHoursPage()
    }
}

#Preview("Werkuren, donker") {
    NavigationStack {
        WorkHoursPage()
    }
    .preferredColorScheme(.dark)
}
#endif
