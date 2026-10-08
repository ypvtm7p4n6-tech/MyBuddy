import SwiftUI
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case home, savings, tools
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .savings: return "Savings"
        case .tools: return "Tools"
        }
    }

    func symbol(selected: Bool) -> String {
        switch self {
        case .home: return selected ? "house.fill" : "house"
        case .savings: return selected ? "banknote.fill" : "banknote"
        case .tools: return selected ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver"
        }
    }
}

/// Alle pagina's die je alleen bereikt door op een blok te tikken.
enum Destination: Hashable {
    // Overzicht en Savings
    case overview
    case income
    case expenses
    case distribute
    case pots
    case pot(UUID)
    case bank
    // Savings: beleggingen, doelen
    case portfolio
    case holding(UUID)
    case projection
    case goals
    case goal(UUID)
    case accelerators
    case buffer
    case savingsGoal
    // Tools
    case purchase
    // Dag voor dag: wat er per dag op de bankrekening staat
    case cashflow
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    var homePath: [Destination] = []
    var savingsPath: [Destination] = []
    var toolsPath: [Destination] = []
    var showSettings = false
    /// De pagina waarvan de blokvolgorde wordt aangepast (laat het blad "Volgorde aanpassen" zien).
    var orderPage: BlockPage?

    /// De maand waar je naar kijkt op de Savings-pagina's.
    var focusMonth: YearMonth = YearMonth.current()
    var periodMode: PeriodMode = .month

    /// Tik op een knop in de tabbalk: ga naar die tab en terug naar de hoofdpagina daarvan.
    func select(_ newTab: AppTab) {
        switch newTab {
        case .home: homePath = []
        case .savings: savingsPath = []
        case .tools: toolsPath = []
        }
        tab = newTab
    }

    /// Opent een pagina op de tab waar je nu bent. Staat die pagina al bovenaan, dan gebeurt er niets:
    /// zo komt een snelle dubbele tik niet twee keer op de stapel (en hoef je niet twee keer terug).
    func open(_ destination: Destination) {
        switch tab {
        case .home: if homePath.last != destination { homePath.append(destination) }
        case .savings: if savingsPath.last != destination { savingsPath.append(destination) }
        case .tools: if toolsPath.last != destination { toolsPath.append(destination) }
        }
    }

    /// Schuift de periode op: richting -1 = terug, +1 = vooruit.
    func shiftPeriod(_ direction: Int) {
        focusMonth = focusMonth.adding(direction * periodMode.stepMonths)
    }

    /// Springt naar de huidige maand.
    func resetFocus(to current: YearMonth) {
        focusMonth = current
    }

    /// Zet de Savings-pagina's op de huidige maand en de periode "Maand". Een blok op Home gaat altijd over
    /// deze maand; zonder dit kon de pagina nog op een andere maand of periode staan en een ander getal tonen.
    func showCurrentMonth(_ current: YearMonth) {
        focusMonth = current
        periodMode = .month
    }
}
