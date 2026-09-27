// Debug scenarios: never in a Release build.
#if DEBUG
import SwiftUI
import UzzyCore

/// Replaces the real accounts in the panel with a debug scenario, to review
/// one of its states by eye without touching the accounts.
@Observable
final class ScenarioSwitch {
    /// `nil` while the panel shows the real accounts.
    private(set) var scenario: Scenario?
    /// The core the panel shows: the scenario's, or the real one.
    private(set) var core: UsageCore
    private let realCore: UsageCore

    init(realCore: UsageCore) {
        self.realCore = realCore
        core = realCore
    }

    /// Shows `scenario`, or the real accounts when `nil`. A scenario starts
    /// with its panel open.
    func show(_ scenario: Scenario?, panelIsOpen: Bool) async {
        guard scenario != self.scenario else { return }
        self.scenario = scenario
        core.panelClosed()
        let next = if let scenario { await scenario.start(enabledProviders: realCore.enabledProviders, order: realCore.order) } else { realCore }
        // Another choice came in while this scenario was starting.
        guard self.scenario == scenario else { return }
        core = next
        // Going back to the real accounts never suspends, so `panelIsOpen`
        // still holds here.
        if scenario == nil, panelIsOpen {
            realCore.panelOpened()
        }
    }
}

/// The panel with a bar on top to choose the scenario it shows.
struct ScenarioPanel: View {
    let scenarios: ScenarioSwitch
    let bounds: PanelBounds
    let openSettings: () -> Void
    let choose: @MainActor (Scenario?) -> Void
    @State private var barHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Escenario", selection: Binding(get: { scenarios.scenario }, set: choose)) {
                    Text("Cuentas reales").tag(Scenario?.none)
                    Divider()
                    ForEach(Scenario.all) { scenario in
                        Text(scenario.name).tag(Optional(scenario))
                    }
                }
                .pickerStyle(.menu)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if scenarios.scenario != nil {
                    Text("Datos ficticios")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { barHeight = $0 }
            PanelView(core: scenarios.core, bounds: bounds, heightAbove: barHeight, openSettings: openSettings)
                .id(ObjectIdentifier(scenarios.core))
        }
        .frame(width: PanelLayout.width, alignment: .top)
        .containerBackground(.clear, for: .window)
    }
}
#endif
