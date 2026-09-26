import SwiftUI
import UzzyCore

enum PanelLayout {
    /// Shared by the panel and the debug scenario bar, so the bar cannot
    /// widen the popover past the cards.
    static let width: CGFloat = 360
    /// Room below the screen's visible frame for the popover's arrow and a
    /// gap above the Dock or the bottom edge.
    static let screenMargin: CGFloat = 40
}

/// How tall the panel may grow: the visible frame of the screen its icon is
/// on, less a margin. The app updates it before each opening and when the
/// screens change.
@Observable
final class PanelBounds {
    var maxHeight: CGFloat = .infinity
}

struct PanelView: View {
    let core: UsageCore
    let bounds: PanelBounds
    /// Taken by views above the panel in the same popover.
    var heightAbove: CGFloat = 0
    let openSettings: () -> Void
    @AppStorage("displayMagnitude") private var selectedMagnitude: QuotaMagnitude = .used
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var cardsHeight: CGFloat = 0

    /// The cards keep their own height until the panel would outgrow the
    /// screen; past that they scroll, and the header and footer stay put.
    private var cardsViewportHeight: CGFloat {
        let available = bounds.maxHeight - heightAbove - headerHeight - footerHeight
        return max(0, min(cardsHeight, available))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.appName).font(.headline)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }

            if core.state.cards.isEmpty {
                VStack(spacing: 10) {
                    Text("No hay proveedores activos").font(.headline)
                    Text("Activa un proveedor en Ajustes para ver sus cuotas.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Abrir ajustes", action: openSettings)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    // Recomputes the time left until each reset every minute.
                    TimelineView(.everyMinute) { _ in
                        VStack(spacing: 0) {
                            ForEach(core.state.cards, id: \.provider) { card in
                                CardView(card: card, magnitude: core.state.magnitude, now: core.now())
                                if card.provider != core.state.cards.last?.provider {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { cardsHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: cardsViewportHeight)
            }

            VStack(spacing: 0) {
                Divider()
                HStack {
                    // Quotas live only in memory, so quitting has nothing to save.
                    Button("Salir") { NSApp.terminate(nil) }
                        .accessibilityLabel(Format.quitApp)
                        .accessibilityInputLabels(["Salir", Format.quitApp])
                        .help("\(Format.quitApp) (⌘Q)")
                    Spacer()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 18, height: 18)
                    }
                    .accessibilityLabel(Format.settings)
                    .help("Abrir ajustes (⌘,)")
                    if !core.state.cards.isEmpty {
                        Button(action: core.refresh) {
                            Group {
                                if core.state.isQuerying {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        .accessibilityLabel("Actualizar")
                        .accessibilityValue(core.state.isQuerying ? "Consulta en curso" : "")
                        .help("Consultar las cuotas ahora")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { footerHeight = $0 }
        }
        .frame(width: PanelLayout.width)
        // The popover draws the system's Liquid Glass behind this view. An
        // opaque fill would cover it, so it would ignore the Appearance setting.
        .containerBackground(.clear, for: .window)
        .onAppear { core.show(selectedMagnitude) }
        .onChange(of: selectedMagnitude) { _, magnitude in core.show(magnitude) }
    }
}

private struct CardView: View {
    let card: Card
    let magnitude: QuotaMagnitude
    let now: Date

    private var lastReadAt: Date? {
        let quotas: [Quota]
        switch card.content {
        case .quotas(let values), .stale(let values, _): quotas = values
        default: return nil
        }
        // A missing or uninterpretable figure has no valid reading to date.
        return quotas.compactMap { quota -> Date? in
            switch quota.value {
            case .percent, .spend: quota.readAt
            case .uninterpretable, .unavailable: nil
            }
        }.min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(provider: card.provider, plan: card.plan)
                if let bankedResets = card.bankedResets {
                    BankedResetsButton(count: bankedResets)
                }
                Spacer()
                if let lastReadAt {
                    Text("Última lectura: \(Format.dayAndTime(lastReadAt, now: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch card.content {
            case .loading:
                Message(title: "Consultando cuotas…", detail: "Todavía no hay un dato válido.")
            case .loadingNewAccount:
                Message(
                    title: "Consultando nueva cuenta…",
                    detail: "La sesión de \(card.provider.officialApp) es de otra cuenta. Se borraron las cifras de la anterior."
                )
            case .failed(let failure):
                FailureMessage(failure: failure, provider: card.provider, now: now)
            case .quotas(let quotas):
                QuotasView(quotas: quotas, magnitude: magnitude, now: now)
            case .stale(let quotas, let failure):
                // Why the figures below could not be refreshed.
                FailureMessage(failure: failure, provider: card.provider, now: now)
                QuotasView(quotas: quotas, magnitude: magnitude, now: now)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The provider's name and, when the provider reports it, the account's plan:
/// «Claude · Max». A plan that does not fit is cut before the name is.
private struct CardTitle: View {
    let provider: Provider
    let plan: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(provider.name)
                .fontWeight(.semibold)
                .layoutPriority(1)
            if let plan {
                Text("· \(plan)")
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Format.cardTitle(provider.name, plan: plan))
    }
}

/// The account's banked resets, next to the provider's name: a pill with the
/// count that opens a popover spelling it out. It is not a quota: no bar, no
/// percentage and no reset date.
private struct BankedResetsButton: View {
    let count: Int
    @State private var isShowingDetail = false

    /// A gauge with a backward arrow: a limit set back.
    static let symbol = "gauge.open.righthalf.dotted.with.needle.and.arrow.trianglehead.backward"

    var body: some View {
        Button { isShowingDetail.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: Self.symbol)
                    .font(.caption2)
                Text(count, format: .number)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.fill.secondary, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Format.bankedResets(count))
        .help(Format.bankedResets(count))
        .popover(isPresented: $isShowingDetail, arrowEdge: .bottom) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Self.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.bankedResets(count)).font(.headline)
                    Text(Format.bankedResetsNote(count))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .fixedSize()
        }
    }
}

private struct QuotasView: View {
    let quotas: [Quota]
    let magnitude: QuotaMagnitude
    let now: Date

    var body: some View {
        ForEach(quotas, id: \.period) { quota in
            QuotaView(quota: quota, magnitude: magnitude, now: now)
        }
    }
}

private struct QuotaView: View {
    let quota: Quota
    let magnitude: QuotaMagnitude
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch quota.value {
            // Every remaining figure is calculated as 100 − used, so the card
            // does not mark it: the chosen magnitude already says so.
            case .percent(let percent, _):
                // The label and the bar come from the same value, so they
                // always show the same magnitude.
                HStack(alignment: .firstTextBaseline) {
                    QuotaName(quota: quota)
                    Spacer()
                    Text(Format.percent(percent))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(quota.isStale ? .secondary : .primary)
                    Text(magnitude.name).font(.caption).foregroundStyle(.secondary)
                }
                Bar(fraction: percent / 100)
                    .opacity(quota.isStale ? 0.5 : 1)
                if let reset = quota.reset {
                    Text(Format.reset(reset, now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            // Money, not a quota figure: no magnitude, no bar and no reset.
            case .spend(let spent, let limit):
                HStack(alignment: .firstTextBaseline) {
                    QuotaName(quota: quota)
                    Spacer()
                    Text(Format.usageCredits(spent, limit: limit))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(quota.isStale ? .secondary : .primary)
                }
            // No valid reading of this quota, so no reset or reading time to vouch for.
            case .uninterpretable:
                QuotaNotice(period: quota.period, notice: "Dato no interpretable")
            case .unavailable:
                QuotaNotice(period: quota.period, notice: "Cuota no disponible")
            }
        }
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }
}

/// A quota's name, marked when its figure is stale.
private struct QuotaName: View {
    let quota: Quota

    var body: some View {
        Text(quota.period.name)
        if quota.isStale {
            Text("Desactualizado").font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
    }
}

/// A quota without a percentage to show: no figure and no bar.
private struct QuotaNotice: View {
    let period: QuotaPeriod
    let notice: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(period.name)
            Spacer()
            Text(notice).fontWeight(.semibold).foregroundStyle(.orange)
        }
    }
}

private struct Bar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

private struct Message: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }
}

/// Why the card has no quotas, and what to do about it.
private struct FailureMessage: View {
    let failure: Failure
    let provider: Provider
    let now: Date

    var body: some View {
        switch failure {
        case .noSession:
            Message(title: "Sin sesión", detail: "Inicia sesión en \(provider.officialApp) y pulsa Actualizar.")
        case .sessionWithoutSubscriptionQuotas:
            Message(
                title: "Esta sesión no ofrece cuotas de suscripción",
                detail: "La sesión de \(provider.officialApp) no es de una suscripción (p. ej., usa una clave de API). Inicia sesión con tu suscripción en \(provider.officialApp) y pulsa Actualizar."
            )
        case .sessionAccessDenied:
            Message(
                title: "Sin acceso a la sesión",
                detail: "Se denegó el acceso a la sesión de \(provider.officialApp) en el llavero. Pulsa Actualizar para volver a pedirlo."
            )
        case .sessionStoreUnavailable:
            if provider == .claude {
                Message(
                    title: "Llavero no disponible",
                    detail: "No se pudo leer la sesión de Claude Code en el llavero. Comprueba que esté desbloqueado y pulsa Actualizar."
                )
            } else {
                Message(
                    title: "No se pudo leer la sesión",
                    detail: "No se pudo abrir la sesión de \(provider.officialApp). Comprueba que la app oficial funcione y pulsa Actualizar."
                )
            }
        case .sessionStoreBusy:
            Message(
                title: "Sesión ocupada",
                detail: "La base de datos de \(provider.officialApp) está ocupada. Espera un momento y pulsa Actualizar."
            )
        case .incompatibleSession:
            Message(
                title: "Sesión incompatible",
                detail: "La sesión de \(provider.officialApp) tiene un formato que \(Format.appName) no reconoce."
            )
        case .sessionExpired:
            Message(title: "Sesión vencida", detail: "Renueva la sesión en \(provider.officialApp) y pulsa Actualizar.")
        case .accessRefused:
            Message(
                title: "Acceso rechazado",
                detail: "\(provider.name) rechazó la consulta. Puede ser una restricción de la cuenta; revísala en \(provider.officialApp) y pulsa Actualizar."
            )
        case .reusedSessionRejected:
            Message(
                title: "Sin confirmar",
                detail: "\(provider.name) no aceptó la sesión guardada. Pulsa Actualizar para volver a comprobarla."
            )
        case .offline:
            Message(title: "Sin conexión", detail: "No se pudo conectar con \(provider.name). Pulsa Actualizar para reintentar.")
        case .timedOut:
            Message(title: "Tiempo agotado", detail: "\(provider.name) no respondió a tiempo. Pulsa Actualizar para reintentar.")
        case .serverError(let status):
            Message(title: "Error del servidor", detail: "\(provider.name) respondió con un error (\(status)). Pulsa Actualizar para reintentar.")
        case .rateLimited(let until):
            let when = until.map { "a partir de: \(Format.dayAndTime($0, now: now))" } ?? "en breve"
            Message(title: "Demasiadas consultas", detail: "\(provider.name) pidió esperar. Se volverá a consultar \(when).")
        case .incompatibleResponse, .responseTooLarge:
            Message(
                title: "Respuesta incompatible",
                detail: "\(provider.name) respondió en un formato que \(Format.appName) no reconoce. Puede que haya cambiado su servicio."
            )
        case .incompatibleResetFormat:
            Message(
                title: "Reinicio de Cursor incompatible",
                detail: "Cursor envió la fecha de reinicio en un formato que \(Format.appName) no reconoce. Pulsa Actualizar; si continúa, la integración necesita una actualización."
            )
        }
    }
}

private extension QuotaPeriod {
    var name: String {
        switch self {
        case .fiveHours: "5 horas"
        case .weekly: "Semanal"
        case .lasting(let seconds): Format.duration(seconds: seconds)
        case .billingCycle: "Ciclo de facturación"
        case .usageCredits: "Créditos de uso"
        case .limit(let name, .billingCycle): name
        case .limit(let name, let period): "\(period.name) · \(name)"
        }
    }
}

extension QuotaMagnitude {
    var name: String {
        switch self {
        case .used: "usado"
        case .remaining: "restante"
        }
    }
}

extension Provider {
    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// The app whose session the card reuses.
    var officialApp: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .cursor: "Cursor"
        }
    }
}
