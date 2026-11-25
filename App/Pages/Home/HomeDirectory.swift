import SwiftUI

/// De gids onderaan Home, zoals de voettekst van apple.com: elke pagina van de app in kleine links onder een kopje (de groepen van de
/// Bibliotheek, Hulpmiddelen en Instellingen), zodat alles vanaf Home één tik is. De pagina's komen uit `PageCatalog` (dezelfde namen
/// als in de Bibliotheek en Zoeken); een maandpagina opent op de huidige maand, zoals de rijen van de Bibliotheek.
struct HomeDirectory: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private struct DirectoryLink: Identifiable {
        let title: String
        let destination: Destination
        var id: String { title }
    }

    private struct DirectoryGroup: Identifiable {
        let id: String
        let title: String
        let links: [DirectoryLink]
    }

    private var groups: [DirectoryGroup] {
        var result = LibrarySection.allCases.map { section in
            DirectoryGroup(id: section.rawValue, title: section.title,
                           links: PageCatalog.library(in: section).map { DirectoryLink(title: $0.title, destination: $0.destination) })
        }
        let tools: [Destination] = [.tools, .savingsGoal]
        result.append(DirectoryGroup(id: "tools", title: "Hulpmiddelen",
                                     links: tools.compactMap { d in PageCatalog.info(d).map { DirectoryLink(title: $0.title, destination: d) } }))
        result.append(DirectoryGroup(id: "settings", title: "Instellingen",
                                     links: [DirectoryLink(title: "Instellingen", destination: .settingsRoot),
                                             DirectoryLink(title: SettingsPage.workHours.title, destination: .settings(.workHours)),
                                             DirectoryLink(title: SettingsPage.startDate.title, destination: .settings(.startDate)),
                                             DirectoryLink(title: SettingsPage.data.title, destination: .settings(.data))]))
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Text("Gids")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .topLeading)], alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.links) { link in
                            Button {
                                router.showCurrentMonth(store.now)
                                router.open(link.destination)
                            } label: {
                                Text(link.title)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.accent)
                                    .frame(minHeight: 28, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isLink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .scenePadding(.horizontal)
        .padding(.top, 8)
    }
}
