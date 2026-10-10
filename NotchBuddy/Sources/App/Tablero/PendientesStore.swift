import Foundation
import Combine

// MARK: - Pendientes del tablero
//
// Con permiso de Recordatorios, los pendientes son los recordatorios sin
// terminar del Mac (RecordatoriosLector): el check los marca hechos en la app
// Recordatorios y el reloj los esconde una hora solo en el tablero. Sin
// permiso, es una lista de muestra guardada en UserDefaults.

struct Pendiente: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var titulo: String
    var detalle: String
    var hecho: Bool = false
    var posponerHasta: Date? = nil
    /// Ya paso la fecha del recordatorio.
    var vencido: Bool = false
}

@MainActor
final class PendientesStore: ObservableObject {
    static let shared = PendientesStore()

    @Published private(set) var todos: [Pendiente] = []
    /// true: los pendientes salen de Recordatorios; false: la muestra.
    @Published private(set) var usaRecordatorios = RecordatoriosLector.conAcceso
    /// Ya llego la primera lectura de Recordatorios.
    @Published private(set) var cargado = false
    /// Dijeron que no al permiso: se activa en Configuracion del Sistema.
    @Published private(set) var accesoNegado = false

    private let clave = "tablero.pendientes"
    private let clavePospuestos = "tablero.pendientes.pospuestos"
    /// Recordatorios escondidos con el reloj: id -> hasta cuando.
    private var pospuestos: [String: Date] = [:]

    private init() {
        pospuestos = (UserDefaults.standard.dictionary(forKey: clavePospuestos) as? [String: Date]) ?? [:]
        if !usaRecordatorios { cargarMuestra() }
    }

    /// Los que se muestran: sin hacer, y sin aplazar o con el aplazamiento vencido.
    func visibles(ahora: Date = Date()) -> [Pendiente] {
        todos.filter { p in
            guard !p.hecho else { return false }
            guard let hasta = p.posponerHasta else { return true }
            return hasta <= ahora
        }
    }

    func completar(_ id: String) {
        guard usaRecordatorios else {
            cambiar(id) { $0.hecho = true }
            guardarMuestra()
            return
        }
        // Sale de la vista de una vez; si Recordatorios no lo deja marcar,
        // vuelve a aparecer en la siguiente lectura.
        cambiar(id) { $0.hecho = true }
        _ = RecordatoriosLector.shared.completar(id)
    }

    func posponer(_ id: String, horas: Double = 1) {
        let hasta = Date().addingTimeInterval(horas * 3600)
        cambiar(id) { $0.posponerHasta = hasta }
        if usaRecordatorios {
            pospuestos[id] = hasta
            guardarPospuestos()
        } else {
            guardarMuestra()
        }
    }

    /// Vuelve a la lista de muestra (para seguir probando cuando se vacia).
    func restaurarMuestra() {
        guard !usaRecordatorios else { return }
        todos = TableroMuestra.pendientes
        guardarMuestra()
    }

    /// Pide el permiso de Recordatorios (el aviso de macOS sale la primera vez).
    func conectarRecordatorios() async {
        let concedido = await RecordatoriosLector.shared.pedirAcceso()
        accesoNegado = !concedido
        if concedido { await refrescar() }
    }

    /// Vuelve a leer Recordatorios. Sin permiso (o si lo quitaron), vuelve a la muestra.
    func refrescar() async {
        guard RecordatoriosLector.conAcceso else {
            if usaRecordatorios {
                usaRecordatorios = false
                cargarMuestra()
            }
            return
        }
        let datos = await RecordatoriosLector.shared.pendientes()
        let ahora = Date()
        pospuestos = pospuestos.filter { $0.value > ahora }
        guardarPospuestos()
        todos = Self.ordenar(datos).map { d in
            Pendiente(id: d.id, titulo: d.titulo.isEmpty ? "Sin título" : d.titulo,
                      detalle: Self.detalle(d, ahora: ahora),
                      posponerHasta: pospuestos[d.id],
                      vencido: d.vence.map { $0 < Calendar.current.startOfDay(for: ahora) } ?? false)
        }
        usaRecordatorios = true
        accesoNegado = false
        cargado = true
    }

    // MARK: - Orden y textos

    /// Primero los que tienen fecha (el mas proximo primero), despues los demas.
    private static func ordenar(_ datos: [RecordatorioDato]) -> [RecordatorioDato] {
        datos.sorted { a, b in
            switch (a.vence, b.vence) {
            case let (x?, y?): return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.titulo.localizedCompare(b.titulo) == .orderedAscending
            }
        }
    }

    /// "Vence hoy", "Venció ayer", "Vence el viernes", "Vence el 24 oct."; sin fecha, la lista.
    private static func detalle(_ d: RecordatorioDato, ahora: Date) -> String {
        guard let vence = d.vence else { return d.lista.isEmpty ? "Sin fecha" : d.lista }
        let calendario = Calendar.current
        let dias = calendario.dateComponents([.day], from: calendario.startOfDay(for: ahora),
                                             to: calendario.startOfDay(for: vence)).day ?? 0
        switch dias {
        case ..<(-1): return "Venció el \(fechaCorta.string(from: vence))"
        case -1:      return "Venció ayer"
        case 0:       return "Vence hoy"
        case 1:       return "Vence mañana"
        case 2...6:   return "Vence el \(diaSemana.string(from: vence))"
        default:      return "Vence el \(fechaCorta.string(from: vence))"
        }
    }

    private static let fechaCorta: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let diaSemana: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "EEEE"
        return f
    }()

    // MARK: - Guardado

    private func cargarMuestra() {
        if let data = UserDefaults.standard.data(forKey: clave),
           let guardados = try? JSONDecoder().decode([Pendiente].self, from: data) {
            todos = guardados
        } else {
            todos = TableroMuestra.pendientes
        }
    }

    private func cambiar(_ id: String, _ cambio: (inout Pendiente) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        var p = todos[i]
        cambio(&p)
        todos[i] = p
    }

    private func guardarMuestra() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: clave)
        }
    }

    private func guardarPospuestos() {
        UserDefaults.standard.set(pospuestos, forKey: clavePospuestos)
    }
}
