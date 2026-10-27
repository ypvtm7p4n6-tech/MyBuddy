import Foundation

// De getallen en teksten van de rijen van de Bibliotheek (B7 en par. 1.4 van docs/design2/plan.md). Elke waarde komt uit
// dezelfde bron als de oude kaart die hij vervangt (`income(in:)`, `expenseOverview(in:)`, `monthFigures(_:)`,
// `bankBalanceNowIfKnown`, `LedgerBook`, `totalSaved`, `PortfolioFigures`, `GoalMath.hubSubtitle`, `BufferCalc.summary`);
// hier wordt niets zelf uitgerekend. Zonder SwiftUI: de view zet alleen tekst en kleur neer. De Bibliotheek gaat altijd over de
// huidige maand (B8, K17).

/// De kleur van een waarde in een rij. Kleur draagt nooit alleen de betekenis: het minteken staat in de tekst.
enum LibraryTone: Equatable {
    case normal, negative
}

/// De ondertitel en waarde van één rij.
struct LibraryRowFigures: Equatable {
    var subtitle: String?
    var value: String?
    var tone: LibraryTone

    init(subtitle: String? = nil, value: String? = nil, tone: LibraryTone = .normal) {
        self.subtitle = subtitle
        self.value = value
        self.tone = tone
    }
}

/// De gegevens waar de rijen van de Bibliotheek op rusten. De twee JSON-teksten zijn de bewaarde keuzes van dit account
/// (het concept van de spaardoel-calculator en de instellingen van de noodbuffer); leeg is toegestaan.
struct LibraryFigures {
    let data: FinanceData
    let now: YearMonth
    let today: Date
    let goalDraftJSON: String
    let bufferSetupJSON: String

    init(data: FinanceData, now: YearMonth, today: Date, goalDraftJSON: String = "", bufferSetupJSON: String = "") {
        self.data = data
        self.now = now
        self.today = today
        self.goalDraftJSON = goalDraftJSON
        self.bufferSetupJSON = bufferSetupJSON
    }

    // MARK: Koppen

    /// De kop van een groep: "Deze maand · oktober", de andere groepen zonder toevoeging.
    func sectionTitle(_ section: LibrarySection) -> String {
        if section == .month {
            let index = min(max(now.month, 1), 12) - 1
            return section.title + " · " + Fmt.monthNames[index]
        }
        return section.title
    }

    /// De laatste boekingen voor de groep Recent.
    func recent(limit: Int = 5) -> [RecentItem] {
        RecentActivity.items(in: data, asOf: today, limit: limit)
    }

    // MARK: Rijen

    /// Ondertitel en waarde van de rij van een pagina; een pagina zonder rij of zonder cijfers geeft een lege regel.
    func row(for destination: Destination) -> LibraryRowFigures {
        switch destination {
        case .flow: return LibraryRowFigures(subtitle: "Waar gaat je geld heen")
        case .income: return incomeRow()
        case .expenses: return expensesRow()
        case .distribute: return distributeRow()
        case .bank: return bankRow()
        case .cashflow: return cashflowRow()
        case .pots: return potsRow()
        case .portfolio: return portfolioRow()
        case .goals: return goalsRow()
        case .buffer: return bufferRow()
        case .accelerators: return acceleratorsRow()
        case .projection: return LibraryRowFigures(subtitle: "Wat is het over x jaar?")
        case .purchase: return LibraryRowFigures(subtitle: "Is het je werkuren waard?")
        default: return LibraryRowFigures()
        }
    }

    // MARK: Deze maand

    /// Inkomen van de maand; onder het bedrag Salaris en Overige inkomsten als er overige inkomsten zijn.
    private func incomeRow() -> LibraryRowFigures {
        if now < data.startMonth {
            return LibraryRowFigures(subtitle: beforeStartText)
        }
        let salary = data.salaryAmount(in: now)
        let extra = data.extraIncomeTotal(in: now)
        let value = Fmt.euro(data.income(in: now))
        if salary == 0 && extra == 0 {
            return LibraryRowFigures(subtitle: "Stel je salaris in", value: value)
        }
        if extra > 0 {
            return LibraryRowFigures(subtitle: "Salaris \(Fmt.euro(salary)) · overige inkomsten \(Fmt.euro(extra))", value: value)
        }
        return LibraryRowFigures(value: value)
    }

    /// Uitgaven van de maand, verdeeld in Vast en Variabel.
    private func expensesRow() -> LibraryRowFigures {
        if now < data.startMonth {
            return LibraryRowFigures(subtitle: beforeStartText)
        }
        let overview = data.expenseOverview(in: now)
        let value = Fmt.euro(overview.expenses)
        if overview.expenses == 0 {
            return LibraryRowFigures(subtitle: "Vul je vaste en variabele uitgaven in", value: value)
        }
        return LibraryRowFigures(subtitle: "Vast \(Fmt.euro(overview.fixed)) · variabel \(Fmt.euro(overview.variable))", value: value)
    }

    /// Wat er van de maand nog te verdelen is, met het teken van het bedrag; negatief krijgt de kleur van een tekort.
    private func distributeRow() -> LibraryRowFigures {
        let figures = data.monthFigures(now)
        let left = CentsMath.value(figures.remaining)
        guard figures.remaining < 0 else {
            return LibraryRowFigures(subtitle: MoneyLabels.remainingLabel(of: now, current: now), value: Fmt.euro(left))
        }
        // Onder nul door te hoge uitgaven (bijvoorbeeld nog geen salaris) is niet "te veel verdeeld".
        let text = figures.available < 0 ? "Je uitgaven zijn hoger dan je inkomen" : "Je hebt te veel verdeeld"
        return LibraryRowFigures(subtitle: text, value: Fmt.euro(left), tone: .negative)
    }

    /// Het saldo van vandaag, alleen als dat bekend is; anders een uitnodiging om het in te vullen.
    private func bankRow() -> LibraryRowFigures {
        guard let balance = data.bankBalanceNowIfKnown(current: now, today: today) else {
            let text = data.hasBankBalance ? "Vul je saldo van vandaag in" : "Vul je saldo in"
            return LibraryRowFigures(subtitle: text)
        }
        return LibraryRowFigures(subtitle: "Saldo vandaag", value: Fmt.euro(balance), tone: balance < 0 ? .negative : .normal)
    }

    /// Het laagste saldo vanaf vandaag, uit de dagboekhouding (hetzelfde saldo als op de dagkaarten van Dag voor dag).
    private func cashflowRow() -> LibraryRowFigures {
        guard data.hasBankBalance else {
            return LibraryRowFigures(subtitle: "Vul je saldo in, dan zie je per dag hoeveel je hebt")
        }
        let book = LedgerBook(data, today: today)
        let window = BankLowPointWindow.range(for: now, current: now, today: today)
        let days = book.days(from: window.from, to: window.to)
        guard let low = CashflowLowPoint.lowest(in: days), let balance = low.bankBalance else {
            return LibraryRowFigures(subtitle: "Voor deze maand is er nog geen saldo per dag bekend")
        }
        let text = "Laagste saldo vanaf vandaag · " + DayText.weekdayShort(low.date)
        return LibraryRowFigures(subtitle: text, value: Fmt.euro(balance), tone: balance < 0 ? .negative : .normal)
    }

    // MARK: Sparen en beleggen

    /// Het totaal gespaard (saldo van vandaag) en het aantal potten.
    private func potsRow() -> LibraryRowFigures {
        let count = data.pots.count
        if count == 0 {
            return LibraryRowFigures(subtitle: "Nog geen spaarpotten")
        }
        let text = count == 1 ? "1 pot" : "\(count) potten"
        return LibraryRowFigures(subtitle: text, value: Fmt.euro(data.totalSaved(current: now, today: today)))
    }

    /// De waarde van de beleggingen en het aantal; zonder koersen of waarde-updates staat er "geschat" bij.
    private func portfolioRow() -> LibraryRowFigures {
        let count = data.holdings.count
        if count == 0 {
            return LibraryRowFigures(subtitle: "Nog geen beleggingen")
        }
        let figures = PortfolioFigures(data, current: now, today: today)
        var text = count == 1 ? "1 belegging" : "\(count) beleggingen"
        if figures.isEstimated {
            text += " · geschat"
        }
        return LibraryRowFigures(subtitle: text, value: Fmt.euro(figures.value))
    }

    // MARK: Plannen

    /// "2 doelen en een spaardoel": het spaardoel telt mee zodra je in de calculator zelf iets hebt ingevuld.
    private func goalsRow() -> LibraryRowFigures {
        let text = GoalMath.hubSubtitle(goalCount: data.goals.count, hasSavingsGoal: hasSavingsPlan)
        return LibraryRowFigures(subtitle: text)
    }

    /// Het plan uit de spaardoel-calculator bestaat zodra je zelf iets hebt ingevuld en het bedrag meer dan nul is.
    private var hasSavingsPlan: Bool {
        guard let draft = SavingsGoalDraft.decode(goalDraftJSON), draft.edited else { return false }
        let plan = draft.plan(savingsRate: data.settings.savingsRate, inflation: data.settings.inflation, now: now)
        return plan.cleanGoal > 0
    }

    /// Hoeveel maanden aan uitgaven de noodbuffer dekt, met de keuzes die op de pagina Noodbuffer zijn bewaard.
    private func bufferRow() -> LibraryRowFigures {
        let setup = BufferSetup.fromJSON(bufferSetupJSON) ?? BufferCalc.initialSetup(for: data, current: now)
        let result = BufferCalc.summary(for: data, setup: setup, current: now, today: today)
        if result.hasTarget {
            return LibraryRowFigures(subtitle: "\(result.months) maanden aan uitgaven")
        }
        return LibraryRowFigures(subtitle: "Vul je uitgaven in")
    }

    /// Versnellers gaan over het eerste doel.
    private func acceleratorsRow() -> LibraryRowFigures {
        guard let goal = data.goals.first else {
            return LibraryRowFigures(subtitle: "Maak eerst een doel")
        }
        return LibraryRowFigures(subtitle: "Voor \(goal.name)")
    }

    // MARK: Teksten

    private var beforeStartText: String {
        "Telt mee vanaf je startmaand (\(Fmt.month(data.startMonth)))"
    }
}
