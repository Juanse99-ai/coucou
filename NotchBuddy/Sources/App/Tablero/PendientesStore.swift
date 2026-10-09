import Foundation
import Combine

// MARK: - Pendientes del tablero
//
// Lista propia del panel, guardada en UserDefaults. El check la marca hecha y
// el reloj la esconde una hora. Arranca con los de TableroMuestra; mas
// adelante puede leer de Recordatorios de Apple.

struct Pendiente: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var titulo: String
    var detalle: String
    var hecho: Bool = false
    var posponerHasta: Date? = nil
}

@MainActor
final class PendientesStore: ObservableObject {
    static let shared = PendientesStore()

    @Published private(set) var todos: [Pendiente] = []

    private let clave = "tablero.pendientes"

    private init() {
        if let data = UserDefaults.standard.data(forKey: clave),
           let guardados = try? JSONDecoder().decode([Pendiente].self, from: data) {
            todos = guardados
        } else {
            todos = TableroMuestra.pendientes
        }
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
        cambiar(id) { $0.hecho = true }
    }

    func posponer(_ id: String, horas: Double = 1) {
        let hasta = Date().addingTimeInterval(horas * 3600)
        cambiar(id) { $0.posponerHasta = hasta }
    }

    /// Vuelve a la lista de muestra (para seguir probando cuando se vacia).
    func restaurarMuestra() {
        todos = TableroMuestra.pendientes
        guardar()
    }

    private func cambiar(_ id: String, _ cambio: (inout Pendiente) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        var p = todos[i]
        cambio(&p)
        todos[i] = p
        guardar()
    }

    private func guardar() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: clave)
        }
    }
}
