import Foundation
import IOKit.ps
import Network

// MARK: - Tablero: lo que pasa en el Mac
//
// Anota cuando se conecta o se quita el cargador y cuando se cae o vuelve el
// internet, para la tarjeta Novedades y el vigilante de Internet. Escucha los
// avisos del sistema (IOKit y NWPathMonitor) en vez de preguntar cada tanto,
// asi que no gasta CPU mientras no pase nada. Arranca con la app
// (AppDelegate) para no perderse lo que pasa con el tablero cerrado.

@MainActor
final class TableroEventos: ObservableObject {
    static let shared = TableroEventos()

    struct Evento: Identifiable, Codable, Sendable {
        let id: UUID
        let texto: String
        let estado: TableroEstado
        let fecha: Date
    }

    /// Los de hoy, el mas reciente primero.
    @Published private(set) var eventos: [Evento] = []
    /// Hay internet. nil hasta el primer aviso del sistema.
    @Published private(set) var conectado: Bool?

    private var enCorriente: Bool?
    private var monitor: NWPathMonitor?
    private var fuenteEnergia: CFRunLoopSource?
    private let clave = "tablero.eventos"

    private init() {}

    func empezar() {
        guard monitor == nil else { return }
        cargar()

        enCorriente = Self.leerEnCorriente()
        if let fuente = IOPSNotificationCreateRunLoopSource(Self.avisoEnergia(), nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), fuente, .defaultMode)
            fuenteEnergia = fuente
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = Self.avisoRed()
        monitor.start(queue: DispatchQueue(label: "tablero.red", qos: .utility))
        self.monitor = monitor
    }

    // Los avisos llegan fuera del MainActor: se arman en un contexto no aislado
    // y solo pasan un Bool al MainActor.
    nonisolated private static func avisoEnergia() -> IOPowerSourceCallbackType {
        return { _ in
            Task { @MainActor in TableroEventos.shared.cambioEnergia() }
        }
    }

    nonisolated private static func avisoRed() -> @Sendable (NWPath) -> Void {
        return { camino in
            let hay = camino.status == .satisfied
            Task { @MainActor in TableroEventos.shared.cambioRed(hay) }
        }
    }

    private func cambioEnergia() {
        // El aviso llega tambien cuando cambia el porcentaje: solo cuenta el enchufe.
        guard let ahora = Self.leerEnCorriente(), ahora != enCorriente else { return }
        let antes = enCorriente
        enCorriente = ahora
        guard antes != nil else { return }
        agregar(ahora ? "Cargador conectado" : "Cargador desconectado", ahora ? .bien : .aviso)
    }

    private func cambioRed(_ hay: Bool) {
        let antes = conectado
        conectado = hay
        guard let antes, antes != hay else { return }
        agregar(hay ? "Internet de vuelta" : "Sin internet", hay ? .bien : .falla)
    }

    /// true si el Mac esta conectado a la corriente. nil si no se pudo leer.
    nonisolated private static func leerEnCorriente() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let tipo = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return nil }
        return (tipo as String) == "AC Power"
    }

    private func agregar(_ texto: String, _ estado: TableroEstado) {
        let inicio = Calendar.current.startOfDay(for: Date())
        eventos.insert(Evento(id: UUID(), texto: texto, estado: estado, fecha: Date()), at: 0)
        eventos = Array(eventos.filter { $0.fecha >= inicio }.prefix(30))
        guardar()
    }

    private func cargar() {
        guard let data = UserDefaults.standard.data(forKey: clave),
              let guardados = try? JSONDecoder().decode([Evento].self, from: data) else { return }
        let inicio = Calendar.current.startOfDay(for: Date())
        eventos = guardados.filter { $0.fecha >= inicio }
    }

    private func guardar() {
        if let data = try? JSONEncoder().encode(eventos) {
            UserDefaults.standard.set(data, forKey: clave)
        }
    }
}
